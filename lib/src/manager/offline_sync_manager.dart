import 'dart:async';
import '../core/sync_task.dart';
import '../core/sync_operation.dart';
import '../core/sync_status.dart';
import '../core/sync_result.dart';
import '../core/sync_config.dart';
import '../store/sync_store.dart';
import '../adapter/sync_adapter.dart';
import '../network/connectivity_service.dart';
import '../retry/retry_policy.dart';
import '../lifecycle/app_lifecycle_observer.dart';
import '../conflict/conflict_detector.dart';
import '../conflict/conflict_resolution.dart';
import '../conflict/conflict_strategy.dart';
import '../conflict/resolution_result.dart';
import '../conflict/resolvers.dart';
import '../dirty_tracking/dirty_tracker.dart';
import '../dirty_tracking/dirty_state.dart';
import '../dirty_tracking/dirty_payload_builder.dart';
import '../debug/sync_debug_controller.dart';
import '../debug/sync_debug_snapshot.dart';
import '../debug/sync_event_type.dart';

/// Core engine for managing offline sync operations.
///
/// Responsibilities:
/// - Prevents duplicate sync tasks using deterministic taskIds
/// - Prevents parallel sync execution (single-flight pattern)
/// - Manages task lifecycle (pending -> syncing -> synced/failed)
/// - Handles batch sync with partial success support
/// - Ensures crash-safety and restart-safety
/// - Auto-syncs on network reconnect and app resume
/// - Implements retry backoff to prevent sync storms
class OfflineSyncManager {
  final SyncStore _store;
  final SyncAdapter _adapter;
  final SyncConfig _config;
  final ConnectivityService? _connectivityService;
  final RetryPolicy _retryPolicy;
  final ConflictDetector _conflictDetector;
  final ConflictResolver _conflictResolver;
  final DirtyTracker? _dirtyTracker;
  final SyncDebugController? _debugController;

  /// Flag to prevent parallel sync execution.
  bool _isSyncing = false;

  /// Completer for the current sync operation, if any.
  Completer<void>? _syncCompleter;

  /// Stream subscription for connectivity changes.
  StreamSubscription<bool>? _connectivitySubscription;

  /// App lifecycle observer for detecting app resume.
  AppLifecycleObserver? _lifecycleObserver;

  /// Timer for delayed retry attempts.
  Timer? _retryTimer;

  /// Whether auto-sync is enabled.
  bool _autoSyncEnabled = false;

  /// Whether the manager has been disposed.
  bool _isDisposed = false;

  /// Creates an [OfflineSyncManager] with the given store, adapter, and config.
  ///
  /// Optionally accepts [connectivityService] for network awareness.
  /// If provided, enables auto-sync on network reconnect.
  ///
  /// Optionally accepts [retryPolicy] for configuring retry backoff.
  /// If not provided, uses default retry policy.
  OfflineSyncManager({
    required SyncStore store,
    required SyncAdapter adapter,
    SyncConfig? config,
    ConnectivityService? connectivityService,
    RetryPolicy? retryPolicy,
    ConflictDetector? conflictDetector,
    DirtyTracker? dirtyTracker,
    SyncDebugController? debugController,
  })  : _store = store,
        _adapter = adapter,
        _config = config ?? SyncConfig.defaults(),
        _connectivityService = connectivityService,
        _conflictDetector = conflictDetector ?? const DefaultConflictDetector(),
        _conflictResolver = _createConflictResolver(
          config?.conflictStrategy ?? ConflictStrategy.lastWriteWins,
          config?.customConflictResolver,
        ),
        _dirtyTracker = dirtyTracker,
        _debugController = debugController,
        _retryPolicy = retryPolicy ?? RetryPolicy.defaults();

  /// Creates the appropriate conflict resolver based on strategy.
  static ConflictResolver _createConflictResolver(
    ConflictStrategy strategy,
    ConflictResolver? customResolver,
  ) {
    switch (strategy) {
      case ConflictStrategy.lastWriteWins:
        return const LastWriteWinsResolver();
      case ConflictStrategy.serverWins:
        return const ServerWinsResolver();
      case ConflictStrategy.clientWins:
        return const ClientWinsResolver();
      case ConflictStrategy.fieldLevelMerge:
        return const FieldLevelMergeResolver();
      case ConflictStrategy.custom:
        if (customResolver == null) {
          throw ArgumentError(
            'customConflictResolver must be provided when '
            'conflictStrategy is ConflictStrategy.custom',
          );
        }
        return customResolver;
    }
  }

  /// Enqueues a new sync task or updates an existing one.
  ///
  /// If a task with the same entityType, entityId, and operation already exists,
  /// it will be overwritten with the new payload. This prevents duplicates
  /// and ensures the latest data is synced.
  ///
  /// The taskId is deterministic and derived from:
  /// - entityType
  /// - entityId
  /// - operation
  ///
  /// This ensures that multiple updates to the same entity will overwrite
  /// the same task, preventing data duplication.
  ///
  /// If [dirtyTracker] is provided and has dirty state for this entity,
  /// only dirty fields will be synced (partial update).
  Future<void> enqueue({
    required String entityType,
    required String entityId,
    required SyncOperation operation,
    required Map<String, dynamic> payload,
  }) async {
    // Check for dirty state if dirty tracker is available
    DirtyState? dirtyState;
    Map<String, dynamic> finalPayload = payload;

    if (_dirtyTracker != null) {
      dirtyState = await _dirtyTracker!.getDirtyState(entityType, entityId);
      
      // If dirty state exists and has dirty fields, build partial payload
      if (dirtyState.hasDirtyFields) {
        finalPayload = DirtyPayloadBuilder.buildPartialPayload(
          fullPayload: payload,
          dirtyState: dirtyState,
        );
      }
    }

    final task = SyncTask(
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      payload: finalPayload,
      status: SyncStatus.pending,
      dirtyState: dirtyState,
    );

    // Save or overwrite the task (taskId is deterministic, so this is safe)
    await _store.saveTask(task);

    // Emit debug event (safe, non-blocking)
    _safeEmitEvent(
      SyncEventType.enqueue,
      taskId: task.taskId,
      entityType: entityType,
      message: 'Task enqueued',
      metadata: {
        'isPartialUpdate': task.isPartialUpdate,
        'dirtyFieldCount': task.dirtyState?.dirtyFieldPaths.length ?? 0,
      },
    );

    // Update metrics (safe, non-blocking)
    _safeUpdateMetrics(() => _debugController?.metrics.incrementEnqueued());
  }

  /// Enables auto-sync triggers.
  ///
  /// When enabled, sync will automatically run when:
  /// - Network becomes available (if connectivityService is provided)
  /// - App resumes from background
  ///
  /// Auto-sync respects connectivity status and will not sync when offline.
  void enableAutoSync() {
    if (_isDisposed || _autoSyncEnabled) return;

    _autoSyncEnabled = true;

    // Listen to connectivity changes
    if (_connectivityService != null) {
      _connectivitySubscription = _connectivityService!.onStatusChange.listen(
        (isOnline) {
          if (isOnline && !_isDisposed) {
            _scheduleSync();
          }
        },
      );
    }

    // Listen to app lifecycle changes
    _lifecycleObserver = AppLifecycleObserver(
      onResume: () {
        if (!_isDisposed) {
          _scheduleSync();
        }
      },
    );
    _lifecycleObserver!.attach();
  }

  /// Disables auto-sync triggers.
  ///
  /// Manual sync via [sync()] will still work.
  void disableAutoSync() {
    _autoSyncEnabled = false;
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _lifecycleObserver?.detach();
    _lifecycleObserver = null;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  /// Syncs pending tasks to the server.
  ///
  /// This method implements single-flight pattern to prevent parallel execution.
  /// If a sync is already in progress, subsequent calls will wait for it to complete.
  ///
  /// Process:
  /// 1. Check connectivity (if connectivityService is provided)
  /// 2. Fetch pending tasks in batches
  /// 3. Mark tasks as syncing BEFORE network call (crash-safe)
  /// 4. Call adapter.syncBatch
  /// 5. Mark successful taskIds as synced
  /// 6. Mark failed taskIds with error and increment retryCount
  ///
  /// Tasks are NEVER deleted without explicit server acknowledgment.
  /// Retries do NOT create new tasks; they update existing ones.
  ///
  /// Will not sync if offline (when connectivityService is provided).
  Future<void> sync() async {
    if (_isDisposed) {
      throw StateError('OfflineSyncManager has been disposed');
    }

    // Check connectivity if service is available
    if (_connectivityService != null) {
      final isOnline = await _connectivityService!.isOnline();
      if (!isOnline) {
        // Don't sync when offline
        _safeEmitEvent(
          SyncEventType.skippedOffline,
          message: 'Sync skipped - device is offline',
        );
        return;
      }
    }

    // Record sync start for metrics
    _safeUpdateMetrics(() => _debugController?.recordSyncStart());

    // Single-flight pattern: prevent parallel sync execution
    if (_isSyncing) {
      // Wait for the current sync to complete
      if (_syncCompleter != null) {
        return _syncCompleter!.future;
      }
    }

    _isSyncing = true;
    _syncCompleter = Completer<void>();

    try {
      await _performSync();
      _syncCompleter!.complete();
    } catch (e) {
      _syncCompleter!.completeError(e);
      rethrow;
    } finally {
      _isSyncing = false;
      _syncCompleter = null;
      
      // Record sync completion for metrics (safe, non-blocking)
      _safeUpdateMetrics(() {
        // Note: hadFailures will be determined in _performSync
        _debugController?.recordSyncComplete();
      });
    }
  }

  /// Schedules a sync attempt, respecting retry delays and preventing overlapping syncs.
  ///
  /// This is used internally by auto-sync triggers.
  void _scheduleSync() {
    if (_isDisposed || _isSyncing) return;

    // Cancel any existing retry timer
    _retryTimer?.cancel();

    // Schedule immediate sync (no delay for auto-triggers)
    _retryTimer = Timer(Duration.zero, () {
      if (!_isDisposed) {
        sync().catchError((error) {
          // Silently handle errors from auto-sync
          // Manual sync errors are still propagated
        });
      }
    });
  }

  /// Performs the actual sync operation.
  Future<void> _performSync() async {
    // Fetch pending tasks in batches
    // Filter out tasks that have exceeded max retries
    final allTasks = await _store.getPendingTasks(_config.batchSize * 2);
    final tasks = allTasks.where((task) {
      return _retryPolicy.shouldRetry(task.retryCount);
    }).take(_config.batchSize).toList();

    if (tasks.isEmpty) {
      return;
    }

    // Check connectivity again right before sync (defensive)
    if (_connectivityService != null) {
      final isOnline = await _connectivityService!.isOnline();
      if (!isOnline) {
        // Network dropped, don't sync
        return;
      }
    }

    // Mark all tasks as syncing BEFORE network call (crash-safe)
    // If the app crashes here, tasks will remain in syncing state
    // and can be recovered on next sync attempt
    for (final task in tasks) {
      await _store.markSyncing(task.taskId);
    }

    // Call adapter to sync batch
    SyncResult result;
    bool hadFailures = false;
    try {
      result = await _adapter.syncBatch(tasks);
      hadFailures = result.failedTaskErrors.isNotEmpty;
    } catch (e) {
      // Network error or adapter exception
      // Mark all tasks as failed and schedule retry if needed
      final errorMessage = e.toString();
      for (final task in tasks) {
        await _store.markFailed(task.taskId, errorMessage);
        _safeEmitEvent(
          SyncEventType.taskFailed,
          taskId: task.taskId,
          entityType: task.entityType,
          message: 'Task failed: $errorMessage',
          metadata: {'retryCount': task.retryCount},
        );
        _safeUpdateMetrics(() {
          _debugController?.metrics.incrementFailed();
        });
      }
      _scheduleRetryIfNeeded(tasks);
      
      // Record sync completion with failures
      _safeUpdateMetrics(() {
        _debugController?.recordSyncComplete(hadFailures: true);
      });
      return;
    }

    // Process successful taskIds
    for (final taskId in result.successTaskIds) {
      await _store.markSynced(taskId);
      
      final task = tasks.firstWhere(
        (t) => t.taskId == taskId,
        orElse: () => throw StateError('Task not found: $taskId'),
      );
      
      // Emit success event
      _safeEmitEvent(
        SyncEventType.taskSucceeded,
        taskId: taskId,
        entityType: task.entityType,
        message: 'Task synced successfully',
      );
      _safeUpdateMetrics(() {
        _debugController?.metrics.incrementSynced();
      });
      
      // Clear dirty fields for successfully synced tasks
      if (_dirtyTracker != null) {
        if (task.dirtyState != null && task.dirtyState!.hasDirtyFields) {
          // Clear all dirty fields that were synced
          await _dirtyTracker!.clearSyncedFields(
            entityType: task.entityType,
            entityId: task.entityId,
            syncedFieldPaths: task.dirtyState!.dirtyFieldPaths,
          );
        }
      }
    }

    // Process failed taskIds with conflict detection and resolution
    final failedTasks = <SyncTask>[];
    for (final entry in result.failedTaskErrors.entries) {
      final taskId = entry.key;
      final error = entry.value;

      // Find the task
      final task = tasks.firstWhere(
        (t) => t.taskId == taskId,
        orElse: () => throw StateError('Task not found: $taskId'),
      );

      // Get server data if available (for conflict detection)
      final serverData = result.serverData?[taskId];

      // Detect conflict
      final conflictResult = _conflictDetector.detect(
        localTask: task,
        serverResponse: serverData,
        errorMessage: error,
      );

      if (conflictResult.hasConflict && conflictResult.serverData != null) {
        // Conflict detected - resolve it
        _safeEmitEvent(
          SyncEventType.conflictDetected,
          taskId: taskId,
          entityType: task.entityType,
          message: 'Conflict detected',
          metadata: conflictResult.metadata,
        );
        _safeUpdateMetrics(() {
          _debugController?.metrics.incrementConflictsDetected();
        });
        
        await _handleConflict(task, conflictResult.serverData!, error);
        
        _safeEmitEvent(
          SyncEventType.conflictResolved,
          taskId: taskId,
          entityType: task.entityType,
          message: 'Conflict resolved',
        );
        _safeUpdateMetrics(() {
          _debugController?.metrics.incrementConflictsResolved();
        });
      } else {
        // No conflict - regular failure
        await _store.markFailed(taskId, error);
        _safeEmitEvent(
          SyncEventType.taskFailed,
          taskId: taskId,
          entityType: task.entityType,
          message: 'Task failed: $error',
          metadata: {'retryCount': task.retryCount},
        );
        _safeUpdateMetrics(() {
          _debugController?.metrics.incrementFailed();
        });
        failedTasks.add(task);
      }
    }

    // Handle tasks that were sent but not acknowledged by server
    // This should not happen if adapter is implemented correctly,
    // but we handle it defensively
    final acknowledgedTaskIds = {
      ...result.successTaskIds,
      ...result.failedTaskErrors.keys,
    };

    for (final task in tasks) {
      if (!acknowledgedTaskIds.contains(task.taskId)) {
        // Task was sent but not acknowledged - mark as failed
        await _store.markFailed(
          task.taskId,
          'Task not acknowledged by server',
        );
        failedTasks.add(task);
      }
    }

    // Schedule retry for failed tasks if needed
    if (failedTasks.isNotEmpty) {
      _scheduleRetryIfNeeded(failedTasks);
    }
    
    // Record sync completion
    _safeUpdateMetrics(() {
      _debugController?.recordSyncComplete(hadFailures: hadFailures);
    });
  }

  /// Safely emits a debug event (non-blocking, never throws).
  void _safeEmitEvent(
    SyncEventType type, {
    String? taskId,
    String? entityType,
    String? message,
    Map<String, Object?>? metadata,
  }) {
    if (_debugController == null) return;
    
    try {
      _debugController!.emitEventNow(
        type: type,
        taskId: taskId,
        entityType: entityType,
        message: message,
        metadata: metadata,
      );
    } catch (e) {
      // Never throw from debug code - fail silently
    }
  }

  /// Safely updates metrics (non-blocking, never throws).
  void _safeUpdateMetrics(void Function() update) {
    if (_debugController == null) return;
    
    try {
      update();
    } catch (e) {
      // Never throw from debug code - fail silently
    }
  }

  /// Handles a conflict by resolving it and applying the resolution result.
  ///
  /// This method:
  /// - Resolves the conflict using the configured resolver
  /// - Updates the task payload if retry is needed (NEVER changes taskId)
  /// - Marks task as synced if resolution accepts server data
  /// - Marks task as failed if resolution aborts
  ///
  /// CRITICAL: Never creates a new task, never changes taskId, never infinite loops.
  ///
  /// To prevent infinite conflict loops:
  /// - If retry count is already high, we abort to prevent endless retries
  /// - Retry policy will eventually stop retries when maxRetries is reached
  Future<void> _handleConflict(
    SyncTask task,
    Map<String, dynamic> serverData,
    String originalError,
  ) async {
    // Safety check: if retries are exhausted, abort conflict resolution
    // This prevents infinite loops where conflict resolution keeps retrying
    if (!_retryPolicy.shouldRetry(task.retryCount)) {
      await _store.markFailed(
        task.taskId,
        'Conflict detected but retries exhausted: $originalError',
      );
      return;
    }

    try {
      // Resolve conflict
      final resolution = _conflictResolver.resolve(
        localTask: task,
        serverData: serverData,
      );

      if (resolution.shouldAbort) {
        // Resolution failed - mark as failed (non-retryable)
        await _store.markFailed(
          task.taskId,
          resolution.errorMessage ?? 'Conflict resolution aborted',
        );
        return;
      }

      if (resolution.shouldRetry) {
        // Update task payload with resolved data and mark as pending for retry
        // CRITICAL: We update the payload but NEVER change taskId
        // Note: We preserve retryCount - it will increment on next failure if it fails again
        // This ensures retry policy eventually stops infinite conflict loops
        
        // For field-level conflict resolution, merge dirty fields with server data
        Map<String, dynamic> resolvedPayload = resolution.resolvedPayload;
        DirtyState? resolvedDirtyState = task.dirtyState;
        
        if (task.dirtyState != null && 
            task.dirtyState!.hasDirtyFields &&
            resolution.resolutionSource == ResolutionSource.merged) {
          // Field-level merge: merge dirty client fields with clean server fields
          resolvedPayload = DirtyPayloadBuilder.mergePartialIntoFull(
            fullPayload: serverData,
            partialPayload: task.payload,
            dirtyState: task.dirtyState!,
          );
          // Keep the same dirty state for retry
          resolvedDirtyState = task.dirtyState;
        }
        
        final updatedTask = SyncTask(
          entityType: task.entityType,
          entityId: task.entityId,
          operation: task.operation,
          payload: resolvedPayload,
          status: SyncStatus.pending,
          retryCount: task.retryCount, // Preserve current count
          createdAt: task.createdAt,
          updatedAt: DateTime.now(),
          dirtyState: resolvedDirtyState,
        );
        await _store.saveTask(updatedTask);
        // Task will be retried in next sync cycle
        // If it conflicts again and retryCount exceeds maxRetries, it will be aborted
      } else {
        // Resolution accepts server data - mark as synced
        // Clear dirty fields since server data is now the source of truth
        if (_dirtyTracker != null && task.dirtyState != null) {
          if (task.dirtyState!.hasDirtyFields) {
            // Clear all dirty fields since we're accepting server data
            await _dirtyTracker!.clearAll(
              entityType: task.entityType,
              entityId: task.entityId,
            );
          }
        }
        await _store.markSynced(task.taskId);
      }
    } catch (e) {
      // Resolution threw an error - mark as failed
      await _store.markFailed(
        task.taskId,
        'Conflict resolution failed: ${e.toString()}',
      );
    }
  }

  /// Schedules a retry attempt for failed tasks using exponential backoff.
  ///
  /// Only schedules if:
  /// - Auto-sync is enabled
  /// - Tasks haven't exceeded max retries
  /// - Not already syncing
  void _scheduleRetryIfNeeded(List<SyncTask> failedTasks) {
    if (!_autoSyncEnabled || _isDisposed || _isSyncing) return;

    // Find the task with the highest retry count to determine delay
    if (failedTasks.isEmpty) return;

    // Note: task.retryCount is the count BEFORE markFailed was called.
    // After markFailed, the retryCount in store is incremented by 1.
    // So we use retryCount + 1 to get the current retry count.
    final maxRetryCount = failedTasks
        .map((t) => t.retryCount + 1)
        .reduce((a, b) => a > b ? a : b);

    final delay = _retryPolicy.nextDelay(maxRetryCount);
    if (delay == null) {
      // Retries exhausted, don't schedule
      return;
    }

    // Cancel any existing retry timer
    _retryTimer?.cancel();

    // Schedule retry with backoff delay
    _retryTimer = Timer(delay, () {
      if (!_isDisposed && !_isSyncing) {
        _safeEmitEvent(
          SyncEventType.retryScheduled,
          message: 'Retry scheduled after ${delay.inSeconds}s',
          metadata: {'retryCount': maxRetryCount, 'delaySeconds': delay.inSeconds},
        );
        _safeUpdateMetrics(() {
          _debugController?.metrics.incrementRetries();
        });
        
        sync().catchError((error) {
          // Silently handle errors from auto-retry
        });
      }
    });
  }

  /// Executes sync in a background context.
  ///
  /// This method is designed to be called from background isolates
  /// (e.g., Android WorkManager, iOS background fetch).
  ///
  /// It performs the same sync operation as [sync()] but is optimized
  /// for background execution:
  /// - Does not throw exceptions (returns false on error)
  /// - Respects all existing sync logic (single-flight, retry, conflicts)
  /// - Safe to call from any isolate
  ///
  /// Returns true if sync was attempted (regardless of success/failure).
  /// Returns false if sync could not be executed.
  Future<bool> runBackgroundSync() async {
    if (_isDisposed) {
      return false;
    }

    try {
      _safeEmitEvent(
        SyncEventType.backgroundSyncTriggered,
        message: 'Background sync triggered',
      );
      
      // Use existing sync() method which handles all the logic
      await sync();
      return true;
    } catch (e) {
      // Fail silently - background sync is best-effort
      return false;
    }
  }

  /// Gets the current debug snapshot (read-only).
  ///
  /// Returns null if debug controller is not provided.
  /// This is a safe, read-only operation that does not affect sync behavior.
  Future<SyncDebugSnapshot?> getDebugSnapshot() async {
    if (_debugController == null) {
      return null;
    }
    
    try {
      return await _debugController!.getCurrentSnapshot();
    } catch (e) {
      // Never throw from debug code
      return null;
    }
  }

  /// Disposes of resources used by this manager.
  ///
  /// Should be called when the manager is no longer needed to prevent memory leaks.
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;

    disableAutoSync();
    _connectivityService?.dispose();
    _retryTimer?.cancel();
    _retryTimer = null;
  }
}

