import 'dart:async';
import '../core/entity_ref.dart';
import '../core/queue_compactor.dart';
import '../core/queue_scheduler.dart';
import '../core/sync_task.dart';
import '../core/sync_operation.dart';
import '../core/sync_priority.dart';
import '../core/sync_report.dart';
import '../core/sync_state.dart';
import '../core/sync_status.dart';
import '../core/sync_result.dart';
import '../core/sync_config.dart';
import '../store/sync_store.dart';
import '../adapter/sync_adapter.dart';
import '../adapters/adapter_errors.dart';
import '../network/connectivity_service.dart';
import '../retry/retry_policy.dart';
import '../resilience/circuit_breaker.dart';
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
/// - Compacts the queue by merging consecutive changes to the same entity
/// - Prevents parallel sync execution (single-flight pattern)
/// - Sends tasks by priority while keeping per-entity order and dependencies
/// - Manages task lifecycle (pending -> syncing -> synced/failed/deadLetter)
/// - Handles batch sync with partial success support, draining the queue
/// - Ensures crash-safety and restart-safety
/// - Never marks a change as synced if it was edited while in flight
/// - Auto-syncs on network reconnect, app resume and (optionally) enqueue
/// - Per-task exponential backoff, a dead-letter queue and a circuit breaker
///   to prevent sync storms
/// - Exposes reactive [SyncState] and per-entity status streams for UI
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
  final CircuitBreaker? _circuitBreaker;
  final DateTime Function() _clock;

  /// Serializes read-modify-write sequences on the store so enqueue and
  /// result handling never interleave.
  final _AsyncLock _lock = _AsyncLock();

  /// The sync currently running, if any (single-flight).
  Future<SyncReport>? _inFlight;

  /// Set when an auto-sync trigger fires during a running sync.
  bool _rerunRequested = false;

  StreamSubscription<bool>? _connectivitySubscription;
  AppLifecycleObserver? _lifecycleObserver;
  Timer? _retryTimer;
  Timer? _enqueueDebounceTimer;

  bool _autoSyncEnabled = false;
  bool _isDisposed = false;
  bool _paused = false;

  /// Last createdAt handed out, used to keep enqueue order strictly monotonic.
  DateTime? _lastEnqueueAt;

  final StreamController<SyncState> _stateController =
      StreamController<SyncState>.broadcast();
  final StreamController<List<SyncTask>> _tasksController =
      StreamController<List<SyncTask>>.broadcast();
  SyncState _state = SyncState.initial;
  List<SyncTask>? _tasksSnapshot;

  /// Creates an [OfflineSyncManager] with the given store, adapter, and config.
  ///
  /// Optionally accepts [connectivityService] for network awareness.
  /// If provided, enables auto-sync on network reconnect.
  ///
  /// Optionally accepts [retryPolicy] for configuring retry backoff. If not
  /// provided, a default policy with `config.maxRetries` is used.
  ///
  /// [clock] can be overridden in tests.
  OfflineSyncManager({
    required SyncStore store,
    required SyncAdapter adapter,
    SyncConfig? config,
    ConnectivityService? connectivityService,
    RetryPolicy? retryPolicy,
    ConflictDetector? conflictDetector,
    DirtyTracker? dirtyTracker,
    SyncDebugController? debugController,
    DateTime Function()? clock,
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
        _clock = clock ?? DateTime.now,
        _circuitBreaker = config?.circuitBreaker == null
            ? null
            : CircuitBreaker(config!.circuitBreaker!, clock: clock),
        _retryPolicy = retryPolicy ??
            RetryPolicy(
                maxRetries: (config ?? SyncConfig.defaults()).maxRetries);

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

  // ---------------------------------------------------------------------------
  // Public state
  // ---------------------------------------------------------------------------

  /// Latest known engine state.
  SyncState get state => _state;

  /// Stream of engine state. Emits the current state on listen, then every
  /// change. Works without debug mode.
  Stream<SyncState> get stateStream => _replaying<SyncState>(
        source: _stateController.stream,
        initial: () async {
          await _ensureSnapshot();
          return _state;
        },
      );

  /// Whether a sync is currently running.
  bool get isSyncing => _inFlight != null;

  /// Whether syncing is paused (see [pause]).
  bool get isPaused => _paused;

  /// Whether auto-sync triggers are enabled.
  bool get isAutoSyncEnabled => _autoSyncEnabled;

  /// Current circuit breaker state, or null if no breaker is configured.
  CircuitState? get circuitState => _circuitBreaker?.state;

  /// Watches the sync status of one entity, for "pending upload" badges.
  ///
  /// Emits the current status on listen, then whenever it changes.
  Stream<EntitySyncStatus> watchEntity(String entityType, String entityId) {
    final key = EntityRef.entityKey(entityType, entityId);
    EntitySyncStatus? last;
    late final StreamController<EntitySyncStatus> controller;
    StreamSubscription<List<SyncTask>>? sub;
    var gotLiveUpdate = false;

    void push(List<SyncTask> tasks) {
      final status =
          QueueScheduler.entityStatus(tasks.where((t) => t.entityKey == key));
      if (status != last && !controller.isClosed) {
        last = status;
        controller.add(status);
      }
    }

    controller = StreamController<EntitySyncStatus>(
      onListen: () async {
        sub = _tasksController.stream.listen((tasks) {
          gotLiveUpdate = true;
          push(tasks);
        });
        final tasks = await _ensureSnapshot();
        if (!gotLiveUpdate) push(tasks);
      },
      onCancel: () => sub?.cancel(),
    );
    return controller.stream;
  }

  /// Current sync status of one entity.
  Future<EntitySyncStatus> getEntityStatus(
      String entityType, String entityId) async {
    final key = EntityRef.entityKey(entityType, entityId);
    final tasks = await _store.getAllTasks();
    return QueueScheduler.entityStatus(tasks.where((t) => t.entityKey == key));
  }

  /// Returns tasks in the queue, optionally filtered by [status].
  Future<List<SyncTask>> getTasks({SyncStatus? status}) async {
    final tasks = await _store.getAllTasks();
    final filtered = status == null
        ? tasks
        : tasks.where((t) => t.status == status).toList();
    return filtered..sort(QueueCompactor.compareQueueOrder);
  }

  /// Tasks that failed permanently and need attention.
  Future<List<SyncTask>> getDeadLetterTasks() =>
      getTasks(status: SyncStatus.deadLetter);

  // ---------------------------------------------------------------------------
  // Enqueue
  // ---------------------------------------------------------------------------

  /// Enqueues a new sync task or folds it into the existing queue.
  ///
  /// The taskId is deterministic (entityType + entityId + operation), so
  /// repeated changes never create duplicates. With
  /// [SyncConfig.coalesceOperations] (on by default) consecutive changes to
  /// the same entity are merged too: create + update becomes one create,
  /// update + delete becomes one delete, and create + delete of an entity
  /// the server never saw is dropped entirely.
  ///
  /// [priority] controls send order across entities. [dependsOn] holds this
  /// task back until the listed entities are fully synced, e.g. a comment
  /// that depends on its post.
  ///
  /// If [dirtyTracker] is provided and has dirty state for this entity,
  /// only dirty fields will be synced (partial update).
  Future<void> enqueue({
    required String entityType,
    required String entityId,
    required SyncOperation operation,
    required Map<String, dynamic> payload,
    SyncPriority priority = SyncPriority.normal,
    List<EntityRef> dependsOn = const [],
  }) async {
    _ensureNotDisposed();

    // Check for dirty state if dirty tracker is available
    DirtyState? dirtyState;
    Map<String, dynamic> finalPayload = payload;

    if (_dirtyTracker != null && operation != SyncOperation.delete) {
      dirtyState = await _dirtyTracker!.getDirtyState(entityType, entityId);

      // If dirty state exists and has dirty fields, build partial payload
      if (dirtyState.hasDirtyFields) {
        finalPayload = DirtyPayloadBuilder.buildPartialPayload(
          fullPayload: payload,
          dirtyState: dirtyState,
        );
      } else {
        dirtyState = null;
      }
    }

    final now = _nextEnqueueTime();
    final incoming = SyncTask(
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      payload: finalPayload,
      status: SyncStatus.pending,
      dirtyState: dirtyState,
      createdAt: now,
      updatedAt: now,
      priority: priority,
      dependsOn: dependsOn,
    );

    final plan = await _lock.run(() async {
      final forEntity = (await _store.getAllTasks())
          .where((t) => t.entityKey == incoming.entityKey && t.isOutstanding)
          .toList();
      final plan = QueueCompactor.plan(
        existing: forEntity,
        incoming: incoming,
        coalesce: _config.coalesceOperations,
      );
      // Save before removing: a crash in between leaves both tasks, which is
      // safe (they are sent in order), whereas the reverse could lose data.
      if (plan.save != null) await _store.saveTask(plan.save!);
      for (final id in plan.remove) {
        await _store.deleteTask(id);
      }
      return plan;
    });

    if (plan.kind == CompactionKind.annihilated && _dirtyTracker != null) {
      await _dirtyTracker!.clearAll(entityType: entityType, entityId: entityId);
    }

    final taskId = plan.save?.taskId ?? incoming.taskId;
    switch (plan.kind) {
      case CompactionKind.merged:
        _safeEmitEvent(SyncEventType.taskCoalesced,
            taskId: taskId,
            entityType: entityType,
            message: 'Change merged into queued task',
            metadata: {'removed': plan.remove});
        _safeUpdateMetrics(
            () => _debugController?.metrics.incrementCoalesced());
        break;
      case CompactionKind.annihilated:
        _safeEmitEvent(SyncEventType.taskAnnihilated,
            taskId: taskId,
            entityType: entityType,
            message: 'Create and delete cancelled out; nothing to send',
            metadata: {'removed': plan.remove});
        _safeUpdateMetrics(
            () => _debugController?.metrics.incrementCoalesced());
        break;
      case CompactionKind.appended:
      case CompactionKind.replaced:
        break;
    }

    _safeEmitEvent(
      SyncEventType.enqueue,
      taskId: taskId,
      entityType: entityType,
      message: 'Task enqueued',
      metadata: {
        'compaction': plan.kind.name,
        'isPartialUpdate': plan.save?.isPartialUpdate ?? false,
        'dirtyFieldCount': plan.save?.dirtyState?.dirtyFieldPaths.length ?? 0,
      },
    );
    _safeUpdateMetrics(() => _debugController?.metrics.incrementEnqueued());

    await _refreshState();
    _scheduleEnqueueSync();
  }

  /// Returns a strictly increasing timestamp so enqueue order is preserved
  /// even on platforms with coarse clocks.
  DateTime _nextEnqueueTime() {
    var now = _clock();
    final last = _lastEnqueueAt;
    if (last != null && !now.isAfter(last)) {
      now = last.add(const Duration(microseconds: 1));
    }
    _lastEnqueueAt = now;
    return now;
  }

  // ---------------------------------------------------------------------------
  // Queue management
  // ---------------------------------------------------------------------------

  /// Moves dead-lettered tasks back into the queue with a fresh retry budget.
  ///
  /// Retries a single task when [taskId] is given, otherwise all of them.
  /// Returns the number of tasks revived.
  Future<int> retryDeadLetter([String? taskId]) async {
    _ensureNotDisposed();
    final revived = await _lock.run(() async {
      final tasks = taskId == null
          ? await _store.getAllTasks()
          : [if (await _store.getTask(taskId) case final t?) t];
      var count = 0;
      for (final task in tasks) {
        if (task.status != SyncStatus.deadLetter) continue;
        await _store.saveTask(task.copyWith(
          status: SyncStatus.pending,
          retryCount: 0,
          clearNextAttemptAt: true,
          updatedAt: _clock(),
        ));
        count++;
        _safeEmitEvent(SyncEventType.taskRevived,
            taskId: task.taskId, entityType: task.entityType);
      }
      return count;
    });
    await _refreshState();
    if (revived > 0) _scheduleSync();
    return revived;
  }

  /// Removes a task from the queue without sending it.
  ///
  /// Tasks that are currently in flight cannot be discarded. Returns true if
  /// a task was removed.
  Future<bool> discardTask(String taskId) async {
    _ensureNotDisposed();
    final removed = await _lock.run(() async {
      final task = await _store.getTask(taskId);
      if (task == null || task.status == SyncStatus.syncing) return false;
      await _store.deleteTask(taskId);
      return true;
    });
    if (removed) await _refreshState();
    return removed;
  }

  /// Removes every dead-lettered task. Returns the number removed.
  Future<int> discardDeadLetters() async {
    _ensureNotDisposed();
    final removed = await _lock.run(() async {
      var count = 0;
      for (final task in await _store.getAllTasks()) {
        if (task.status == SyncStatus.deadLetter) {
          await _store.deleteTask(task.taskId);
          count++;
        }
      }
      return count;
    });
    if (removed > 0) await _refreshState();
    return removed;
  }

  /// Pauses syncing. Manual and automatic syncs are skipped until [resume]
  /// is called (a manual `sync(force: true)` still runs). Enqueueing keeps
  /// working while paused.
  void pause() {
    if (_paused || _isDisposed) return;
    _paused = true;
    _retryTimer?.cancel();
    _enqueueDebounceTimer?.cancel();
    _safeEmitEvent(SyncEventType.paused, message: 'Sync paused');
    if (!isSyncing) _setPhase(SyncPhase.paused);
  }

  /// Resumes syncing after [pause], and syncs right away if auto-sync is on.
  void resume() {
    if (!_paused || _isDisposed) return;
    _paused = false;
    _safeEmitEvent(SyncEventType.resumed, message: 'Sync resumed');
    if (!isSyncing) _setPhase(SyncPhase.idle);
    _scheduleSync();
  }

  /// Closes the circuit breaker, allowing syncs immediately.
  void resetCircuitBreaker() {
    _circuitBreaker?.reset();
    if (_state.phase == SyncPhase.circuitOpen) _setPhase(SyncPhase.idle);
    _scheduleSync();
  }

  // ---------------------------------------------------------------------------
  // Auto-sync
  // ---------------------------------------------------------------------------

  /// Enables auto-sync triggers.
  ///
  /// When enabled, sync will automatically run when:
  /// - Network becomes available (if connectivityService is provided)
  /// - App resumes from background
  /// - A failed task's backoff delay has elapsed
  /// - After [SyncConfig.syncOnEnqueueDebounce], when set
  ///
  /// Auto-sync respects connectivity status and will not sync when offline.
  void enableAutoSync() {
    if (_isDisposed || _autoSyncEnabled) return;

    _autoSyncEnabled = true;

    // Listen to connectivity changes
    if (_connectivityService != null) {
      _connectivitySubscription = _connectivityService!.onStatusChange.listen(
        (isOnline) {
          if (_isDisposed) return;
          if (isOnline) {
            if (_state.phase == SyncPhase.offline) _setPhase(SyncPhase.idle);
            _scheduleSync();
          } else if (!isSyncing && _state.phase == SyncPhase.idle) {
            _setPhase(SyncPhase.offline);
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

    // Pick up anything that is already waiting.
    _scheduleSync();
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
    _enqueueDebounceTimer?.cancel();
    _enqueueDebounceTimer = null;
  }

  /// Schedules a sync attempt from an auto-sync trigger.
  void _scheduleSync([Duration delay = Duration.zero]) {
    if (_isDisposed || !_autoSyncEnabled || _paused) return;
    if (isSyncing) {
      _rerunRequested = true;
      return;
    }

    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      if (_isDisposed || _paused) return;
      sync().catchError((Object _) {
        // Auto-sync errors are swallowed; manual sync errors propagate.
        return const SyncReport();
      });
    });
  }

  void _scheduleEnqueueSync() {
    final debounce = _config.syncOnEnqueueDebounce;
    if (debounce == null || !_autoSyncEnabled || _paused || _isDisposed) {
      return;
    }
    _enqueueDebounceTimer?.cancel();
    _enqueueDebounceTimer = Timer(debounce, () => _scheduleSync());
  }

  /// After a sync, schedules the next automatic attempt if there is work
  /// waiting on a timer (backoff or circuit breaker cooldown).
  void _scheduleFollowUp(SyncReport report) {
    if (_isDisposed || !_autoSyncEnabled || _paused) return;

    if (_rerunRequested) {
      _rerunRequested = false;
      _scheduleSync();
      return;
    }
    if (report.skippedReason == SyncSkipReason.offline) return;

    final now = _clock();
    final openUntil = _circuitBreaker?.openUntil;
    if (openUntil != null && openUntil.isAfter(now)) {
      _scheduleSync(openUntil.difference(now));
      return;
    }

    final tasks = _tasksSnapshot ?? const <SyncTask>[];
    final readyNow = QueueScheduler.selectBatch(tasks,
            now: now, limit: 1, canRetry: _retryPolicy.shouldRetry)
        .isNotEmpty;
    if (readyNow && report.batches >= _config.maxBatchesPerSync) {
      _scheduleSync();
      return;
    }

    final nextRetry = _state.nextRetryAt;
    if (nextRetry != null) {
      final delay =
          nextRetry.isAfter(now) ? nextRetry.difference(now) : Duration.zero;
      _scheduleSync(delay);
      _safeEmitEvent(
        SyncEventType.retryScheduled,
        message: 'Retry scheduled after ${delay.inSeconds}s',
        metadata: {'delayMs': delay.inMilliseconds},
      );
      _safeUpdateMetrics(() => _debugController?.metrics.incrementRetries());
    }
  }

  // ---------------------------------------------------------------------------
  // Sync
  // ---------------------------------------------------------------------------

  /// Syncs queued tasks to the server and returns a [SyncReport].
  ///
  /// Single-flight: if a sync is already running, the call joins it.
  ///
  /// The queue is drained batch by batch (up to
  /// [SyncConfig.maxBatchesPerSync]) until it is empty or a batch has
  /// retryable failures. Tasks are marked as syncing before the network call
  /// (crash-safe) and are never removed without explicit server
  /// acknowledgment.
  ///
  /// Skipped (with [SyncReport.skippedReason]) when offline, paused or when
  /// the circuit breaker is open. Pass [force] to ignore pause, the circuit
  /// breaker and per-task backoff delays (connectivity is still checked).
  Future<SyncReport> sync({bool force = false}) {
    if (_isDisposed) {
      throw StateError('OfflineSyncManager has been disposed');
    }
    final running = _inFlight;
    if (running != null) return running;

    _retryTimer?.cancel();
    final future = _runSync(force);
    _inFlight = future;
    return future.then((report) {
      _inFlight = null;
      _scheduleFollowUp(report);
      return report;
    }, onError: (Object error, StackTrace stack) {
      _inFlight = null;
      if (!_isDisposed) _setPhase(SyncPhase.idle);
      _scheduleFollowUp(const SyncReport());
      return Future<SyncReport>.error(error, stack);
    });
  }

  Future<SyncReport> _runSync(bool force) async {
    final startedAt = _clock();

    if (_paused && !force) {
      _setPhase(SyncPhase.paused);
      return const SyncReport.skipped(SyncSkipReason.paused);
    }

    if (_connectivityService != null &&
        !await _connectivityService!.isOnline()) {
      _safeEmitEvent(
        SyncEventType.skippedOffline,
        message: 'Sync skipped - device is offline',
      );
      _setPhase(SyncPhase.offline);
      return const SyncReport.skipped(SyncSkipReason.offline);
    }

    final breaker = _circuitBreaker;
    if (breaker != null && !breaker.allowsRequest && !force) {
      _setPhase(SyncPhase.circuitOpen);
      return const SyncReport.skipped(SyncSkipReason.circuitOpen);
    }

    _safeUpdateMetrics(() => _debugController?.recordSyncStart());
    _setPhase(SyncPhase.syncing);

    final totals = _BatchOutcome();
    var batches = 0;
    try {
      await _lock.run(_recoverInterruptedTasks);

      while (batches < _config.maxBatchesPerSync && !_isDisposed) {
        final batch = await _lock.run(() => _prepareBatch(force, totals));
        await _refreshState();
        if (batch.isEmpty) break;

        batches++;
        final outcome = await _sendBatch(batch);
        totals.add(outcome);

        if (outcome.retryableFailures > 0) break; // Don't hammer the server.
        if (breaker != null && !breaker.allowsRequest) break;
        if (_paused && !force) break;
        if (_connectivityService != null &&
            !await _connectivityService!.isOnline()) {
          break;
        }
      }
    } finally {
      _safeUpdateMetrics(() => _debugController?.recordSyncComplete(
          hadFailures: totals.retryableFailures + totals.deadLettered > 0));
    }

    final report = SyncReport(
      batches: batches,
      attempted: totals.attempted,
      succeeded: totals.succeeded,
      failed: totals.retryableFailures,
      conflicts: totals.conflicts,
      deadLettered: totals.deadLettered,
      duration: _clock().difference(startedAt),
    );

    if (!_isDisposed) {
      final phase = breaker != null && !breaker.allowsRequest
          ? SyncPhase.circuitOpen
          : (_paused ? SyncPhase.paused : SyncPhase.idle);
      _publish(_state.copyWith(
          phase: phase, lastSyncAt: _clock(), lastReport: report));
      await _refreshState();
    }
    return report;
  }

  /// Resets tasks left in `syncing` by a crash or kill back to pending.
  /// Only called while no batch of ours is in flight.
  Future<void> _recoverInterruptedTasks() async {
    for (final task in await _store.getAllTasks()) {
      if (task.status == SyncStatus.syncing) {
        await _store.saveTask(task.copyWith(status: SyncStatus.pending));
      }
    }
  }

  /// Housekeeping plus selecting and claiming the next batch.
  Future<List<SyncTask>> _prepareBatch(bool force, _BatchOutcome totals) async {
    final now = _clock();
    final all = await _store.getAllTasks();
    final live = <SyncTask>[];
    final ttl = _config.taskTimeToLive;

    for (final task in all) {
      if (task.status == SyncStatus.synced) {
        // Purge synced tasks past their retention window.
        if (!now.isBefore(task.updatedAt.add(_config.syncedTaskRetention))) {
          await _store.deleteTask(task.taskId);
          continue;
        }
      } else if (task.status == SyncStatus.pending ||
          task.status == SyncStatus.failed) {
        String? reason;
        if (ttl != null && now.difference(task.createdAt) > ttl) {
          reason = 'Expired: not synced within ${ttl.inSeconds}s';
        } else if (!_retryPolicy.shouldRetry(task.retryCount)) {
          // Legacy records that ran out of retries before dead-lettering existed.
          reason = task.lastError ?? 'Retries exhausted';
        }
        if (reason != null) {
          final parked = task.copyWith(
              status: SyncStatus.deadLetter,
              lastError: reason,
              updatedAt: now,
              clearNextAttemptAt: true);
          await _store.saveTask(parked);
          _onDeadLettered(parked, reason);
          totals.deadLettered++;
          live.add(parked);
          continue;
        }
      }
      live.add(task);
    }

    final selected = QueueScheduler.selectBatch(
      live,
      now: now,
      limit: _config.batchSize,
      canRetry: _retryPolicy.shouldRetry,
      ignoreBackoff: force,
    );

    // Mark all tasks as syncing BEFORE the network call (crash-safe).
    final claimed = <SyncTask>[];
    for (final task in selected) {
      final inFlight =
          task.copyWith(status: SyncStatus.syncing, updatedAt: now);
      await _store.saveTask(inFlight);
      claimed.add(inFlight);
    }
    return claimed;
  }

  /// Sends one batch and records the results.
  Future<_BatchOutcome> _sendBatch(List<SyncTask> batch) async {
    final outcome = _BatchOutcome()..attempted = batch.length;
    final byId = {for (final t in batch) t.taskId: t};

    SyncResult result;
    try {
      result = await _adapter.syncBatch(batch);
    } catch (e) {
      // Network error or adapter exception: the whole batch failed.
      final permanent = e is AdapterError && !e.retryable;
      await _lock.run(() async {
        for (final task in batch) {
          outcome.add(
              await _recordFailure(task, e.toString(), permanent: permanent));
        }
      });
      _recordBreaker(outcome);
      return outcome;
    }

    await _lock.run(() async {
      for (final taskId in result.successTaskIds) {
        final sent = byId[taskId];
        if (sent == null) continue; // Unknown id from the server.
        outcome.add(await _recordSuccess(sent));
      }

      for (final entry in result.failedTaskErrors.entries) {
        final sent = byId[entry.key];
        if (sent == null || result.successTaskIds.contains(entry.key)) {
          continue;
        }
        final error = entry.value;

        final conflict = _conflictDetector.detect(
          localTask: sent,
          serverResponse: result.serverData?[entry.key],
          errorMessage: error,
        );

        if (conflict.hasConflict && conflict.serverData != null) {
          outcome.conflicts++;
          _safeEmitEvent(SyncEventType.conflictDetected,
              taskId: sent.taskId,
              entityType: sent.entityType,
              message: 'Conflict detected',
              metadata: conflict.metadata);
          _safeUpdateMetrics(
              () => _debugController?.metrics.incrementConflictsDetected());
          outcome.add(await _handleConflict(sent, conflict.serverData!, error));
        } else {
          outcome.add(await _recordFailure(sent, error,
              permanent: result.permanentFailureTaskIds.contains(entry.key)));
        }
      }

      // Tasks the adapter didn't report on are treated as failed.
      final acknowledged = {
        ...result.successTaskIds,
        ...result.failedTaskErrors.keys,
      };
      for (final task in batch) {
        if (!acknowledged.contains(task.taskId)) {
          outcome.add(await _recordFailure(
              task, 'Task not acknowledged by server',
              permanent: false));
        }
      }
    });

    _recordBreaker(outcome);
    return outcome;
  }

  void _recordBreaker(_BatchOutcome outcome) {
    final breaker = _circuitBreaker;
    if (breaker == null) return;
    if (outcome.succeeded > 0 || outcome.conflicts > 0) {
      if (breaker.recordSuccess()) {
        _safeEmitEvent(SyncEventType.circuitClosed,
            message: 'Circuit breaker closed');
      }
    } else if (outcome.retryableFailures > 0) {
      if (breaker.recordFailure()) {
        _safeEmitEvent(SyncEventType.circuitOpened,
            message: 'Circuit breaker opened',
            metadata: {'openUntil': breaker.openUntil?.toIso8601String()});
      }
    }
  }

  /// Handles a server acknowledgment for [sent].
  Future<_TaskOutcome> _recordSuccess(SyncTask sent) async {
    final current = await _store.getTask(sent.taskId);
    if (current == null) return _TaskOutcome.none;

    if (current.revision != sent.revision) {
      // Edited while in flight: the server has the old content, so keep the
      // newer content queued instead of marking it synced.
      await _store.saveTask(current.copyWith(
        status: SyncStatus.pending,
        retryCount: 0,
        clearNextAttemptAt: true,
        clearLastError: true,
      ));
      return _TaskOutcome.succeeded;
    }

    await _completeTask(current);

    _safeEmitEvent(SyncEventType.taskSucceeded,
        taskId: sent.taskId,
        entityType: sent.entityType,
        message: 'Task synced successfully');
    _safeUpdateMetrics(() => _debugController?.metrics.incrementSynced());

    // Clear dirty fields that were synced.
    final dirty = sent.dirtyState;
    if (_dirtyTracker != null && dirty != null && dirty.hasDirtyFields) {
      await _dirtyTracker!.clearSyncedFields(
        entityType: sent.entityType,
        entityId: sent.entityId,
        syncedFieldPaths: dirty.dirtyFieldPaths,
      );
    }
    return _TaskOutcome.succeeded;
  }

  /// Removes a confirmed task, or keeps it as synced during retention.
  Future<void> _completeTask(SyncTask task) async {
    if (_config.syncedTaskRetention == Duration.zero) {
      await _store.deleteTask(task.taskId);
    } else {
      await _store.saveTask(task.copyWith(
        status: SyncStatus.synced,
        updatedAt: _clock(),
        clearNextAttemptAt: true,
        clearLastError: true,
      ));
    }
  }

  /// Records a failure for [sent]: schedules a retry with backoff, or moves
  /// the task to the dead-letter queue.
  Future<_TaskOutcome> _recordFailure(
    SyncTask sent,
    String error, {
    required bool permanent,
  }) async {
    final current = await _store.getTask(sent.taskId);
    if (current == null) return _TaskOutcome.none;
    final now = _clock();

    if (current.revision != sent.revision) {
      // Edited while in flight; the failure was for older content.
      await _store.saveTask(current.copyWith(
          status: SyncStatus.pending, lastError: error, updatedAt: now));
      return _TaskOutcome.retryableFailure;
    }

    final failures = current.retryCount + 1;
    if (permanent || !_retryPolicy.shouldRetry(failures)) {
      final parked = current.copyWith(
        status: SyncStatus.deadLetter,
        retryCount: failures,
        lastError: error,
        updatedAt: now,
        clearNextAttemptAt: true,
      );
      await _store.saveTask(parked);
      _onDeadLettered(parked, error);
      return _TaskOutcome.deadLettered;
    }

    await _store.saveTask(current.copyWith(
      status: SyncStatus.failed,
      retryCount: failures,
      lastError: error,
      updatedAt: now,
      nextAttemptAt: now.add(_retryPolicy.backoffFor(failures)),
    ));
    _safeEmitEvent(SyncEventType.taskFailed,
        taskId: sent.taskId,
        entityType: sent.entityType,
        message: 'Task failed: $error',
        metadata: {'retryCount': failures});
    _safeUpdateMetrics(() => _debugController?.metrics.incrementFailed());
    return _TaskOutcome.retryableFailure;
  }

  void _onDeadLettered(SyncTask task, String reason) {
    _safeEmitEvent(SyncEventType.taskDeadLettered,
        taskId: task.taskId,
        entityType: task.entityType,
        message: 'Task moved to dead-letter queue: $reason',
        metadata: {'retryCount': task.retryCount});
    _safeUpdateMetrics(() => _debugController?.metrics.incrementDeadLettered());
  }

  /// Handles a conflict by resolving it and applying the resolution result.
  ///
  /// Every conflict counts against the retry budget, so a resolver that
  /// keeps producing conflicting payloads cannot loop forever: once retries
  /// are exhausted the task is dead-lettered. Never creates a new task and
  /// never changes the taskId.
  Future<_TaskOutcome> _handleConflict(
    SyncTask sent,
    Map<String, dynamic> serverData,
    String originalError,
  ) async {
    final current = await _store.getTask(sent.taskId);
    if (current == null) return _TaskOutcome.none;
    final now = _clock();

    if (current.revision != sent.revision) {
      // The user edited the entity while it was in flight. Resend the newer
      // content rather than resolving against stale data.
      await _store.saveTask(current.copyWith(
          status: SyncStatus.pending, lastError: originalError));
      return _TaskOutcome.conflictRequeued;
    }

    final failures = current.retryCount + 1;
    Future<_TaskOutcome> park(String reason) async {
      final parked = current.copyWith(
        status: SyncStatus.deadLetter,
        retryCount: failures,
        lastError: reason,
        updatedAt: now,
        clearNextAttemptAt: true,
      );
      await _store.saveTask(parked);
      _onDeadLettered(parked, reason);
      return _TaskOutcome.deadLettered;
    }

    if (!_retryPolicy.shouldRetry(failures)) {
      return park('Conflict unresolved after $failures attempts: '
          '$originalError');
    }

    final ResolutionResult resolution;
    try {
      resolution =
          _conflictResolver.resolve(localTask: current, serverData: serverData);
    } catch (e) {
      return park('Conflict resolution failed: $e');
    }

    if (resolution.shouldAbort) {
      return park(resolution.errorMessage ?? 'Conflict resolution aborted');
    }

    _safeEmitEvent(SyncEventType.conflictResolved,
        taskId: sent.taskId,
        entityType: sent.entityType,
        message: 'Conflict resolved',
        metadata: {'source': resolution.resolutionSource.name});
    _safeUpdateMetrics(
        () => _debugController?.metrics.incrementConflictsResolved());

    if (resolution.shouldRetry) {
      var resolvedPayload = resolution.resolvedPayload;
      final dirty = current.dirtyState;
      if (dirty != null &&
          dirty.hasDirtyFields &&
          resolution.resolutionSource == ResolutionSource.merged) {
        // Field-level merge: dirty client fields over clean server fields.
        resolvedPayload = DirtyPayloadBuilder.mergePartialIntoFull(
          fullPayload: serverData,
          partialPayload: current.payload,
          dirtyState: dirty,
        );
      }
      await _store.saveTask(current.copyWith(
        payload: resolvedPayload,
        status: SyncStatus.pending,
        retryCount: failures,
        lastError: originalError,
        updatedAt: now,
        revision: current.revision + 1,
        clearNextAttemptAt: true,
      ));
      return _TaskOutcome.conflictRequeued;
    }

    // Resolution accepts server data: the server is the source of truth.
    if (_dirtyTracker != null && current.dirtyState != null) {
      await _dirtyTracker!
          .clearAll(entityType: current.entityType, entityId: current.entityId);
    }
    await _completeTask(current);
    return _TaskOutcome.succeeded;
  }

  // ---------------------------------------------------------------------------
  // State plumbing
  // ---------------------------------------------------------------------------

  Future<List<SyncTask>> _ensureSnapshot() async {
    final snapshot = _tasksSnapshot;
    if (snapshot != null) return snapshot;
    await _refreshState();
    return _tasksSnapshot ?? const [];
  }

  /// Reloads tasks from the store and publishes state if it changed.
  Future<void> _refreshState() async {
    if (_isDisposed) return;
    final List<SyncTask> tasks;
    try {
      tasks = await _store.getAllTasks();
    } catch (_) {
      return; // State is best-effort; never break sync over it.
    }
    if (_isDisposed) return;

    var pending = 0, syncing = 0, failed = 0, dead = 0;
    DateTime? nextRetry;
    for (final t in tasks) {
      switch (t.status) {
        case SyncStatus.pending:
          pending++;
          break;
        case SyncStatus.syncing:
          syncing++;
          break;
        case SyncStatus.failed:
          failed++;
          final at = t.nextAttemptAt;
          if (at != null && (nextRetry == null || at.isBefore(nextRetry))) {
            nextRetry = at;
          }
          break;
        case SyncStatus.deadLetter:
          dead++;
          break;
        case SyncStatus.synced:
          break;
      }
    }

    _tasksSnapshot = List.unmodifiable(tasks);
    _tasksController.add(_tasksSnapshot!);
    _publish(_state.copyWith(
      pendingCount: pending,
      syncingCount: syncing,
      failedCount: failed,
      deadLetterCount: dead,
      nextRetryAt: nextRetry,
      clearNextRetryAt: nextRetry == null,
    ));
  }

  void _setPhase(SyncPhase phase) => _publish(_state.copyWith(phase: phase));

  void _publish(SyncState next) {
    if (_isDisposed || next == _state) return;
    _state = next;
    _stateController.add(next);
  }

  /// A stream that emits [initial] on listen, then forwards [source].
  Stream<T> _replaying<T>({
    required Stream<T> source,
    required Future<T> Function() initial,
  }) {
    late final StreamController<T> controller;
    StreamSubscription<T>? sub;
    var gotLiveUpdate = false;
    controller = StreamController<T>(
      onListen: () async {
        sub = source.listen((value) {
          gotLiveUpdate = true;
          controller.add(value);
        }, onDone: controller.close);
        final value = await initial();
        if (!gotLiveUpdate && !controller.isClosed) controller.add(value);
      },
      onCancel: () => sub?.cancel(),
    );
    return controller.stream;
  }

  void _ensureNotDisposed() {
    if (_isDisposed) {
      throw StateError('OfflineSyncManager has been disposed');
    }
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

      final report = await sync();
      return !report.wasSkipped;
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

    disableAutoSync();
    _isDisposed = true;
    _connectivityService?.dispose();
    _retryTimer?.cancel();
    _retryTimer = null;
    _stateController.close();
    _tasksController.close();
  }
}

/// Outcome of a single task within a batch.
enum _TaskOutcome {
  none,
  succeeded,
  retryableFailure,
  deadLettered,
  conflictRequeued,
}

/// Running totals for a batch or a whole sync.
class _BatchOutcome {
  int attempted = 0;
  int succeeded = 0;
  int retryableFailures = 0;
  int deadLettered = 0;
  int conflicts = 0;

  void add(Object other) {
    if (other is _BatchOutcome) {
      attempted += other.attempted;
      succeeded += other.succeeded;
      retryableFailures += other.retryableFailures;
      deadLettered += other.deadLettered;
      conflicts += other.conflicts;
      return;
    }
    switch (other as _TaskOutcome) {
      case _TaskOutcome.succeeded:
        succeeded++;
        break;
      case _TaskOutcome.retryableFailure:
        retryableFailures++;
        break;
      case _TaskOutcome.deadLettered:
        deadLettered++;
        break;
      case _TaskOutcome.conflictRequeued:
      case _TaskOutcome.none:
        break;
    }
  }
}

/// Minimal async mutex: runs actions one at a time, in call order.
class _AsyncLock {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then((_) {}, onError: (Object _) {});
    return result;
  }
}
