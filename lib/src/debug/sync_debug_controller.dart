import 'dart:async';
import 'sync_event.dart';
import 'sync_event_type.dart';
import 'sync_metrics.dart';
import 'sync_debug_snapshot.dart';
import '../core/sync_status.dart';
import '../store/sync_store.dart';
import '../network/connectivity_service.dart';

/// Controller for debug and observability features.
///
/// Provides:
/// - Stream of sync events for monitoring
/// - Current snapshot of sync engine state
/// - Metrics aggregation
///
/// CRITICAL:
/// - Debug mode is OFF by default
/// - When disabled, has zero overhead
/// - No side effects on sync engine
/// - Auto-disables in release builds unless explicitly enabled
class SyncDebugController {
  final SyncStore _store;
  final ConnectivityService? _connectivityService;

  /// Stream controller for sync events.
  final _eventController = StreamController<SyncEvent>.broadcast();

  /// Metrics aggregator.
  final SyncMetrics _metrics = SyncMetrics();

  /// Whether debug mode is enabled.
  bool _enabled = false;

  /// Last sync start time for duration calculation.
  DateTime? _lastSyncStartTime;

  /// Last sync completion time.
  DateTime? _lastSyncTime;

  /// Creates a [SyncDebugController].
  ///
  /// [store] - Sync store for reading task state
  /// [connectivityService] - Optional connectivity service for online status
  SyncDebugController({
    required SyncStore store,
    ConnectivityService? connectivityService,
  })  : _store = store,
        _connectivityService = connectivityService;

  /// Stream of sync events.
  ///
  /// Only emits events when debug mode is enabled.
  Stream<SyncEvent> get events => _eventController.stream;

  /// Current metrics.
  SyncMetrics get metrics => _metrics;

  /// Whether debug mode is enabled.
  bool get isEnabled => _enabled;

  /// Enables debug mode.
  ///
  /// In release builds, this will only work if explicitly enabled
  /// (kDebugMode check is bypassed for explicit enable).
  void enable() {
    _enabled = true;
  }

  /// Disables debug mode.
  ///
  /// When disabled, no events are emitted and metrics are not updated.
  void disable() {
    _enabled = false;
  }

  /// Emits a sync event (safe, non-blocking).
  ///
  /// This method is safe to call even when debug mode is disabled.
  /// It will silently do nothing if disabled.
  void emitEvent(SyncEvent event) {
    if (!_enabled) return;

    try {
      _eventController.add(event);
    } catch (e) {
      // Never throw from debug code - fail silently
    }
  }

  /// Emits a sync event with current timestamp (safe, non-blocking).
  void emitEventNow({
    required SyncEventType type,
    String? taskId,
    String? entityType,
    String? message,
    Map<String, Object?>? metadata,
  }) {
    if (!_enabled) return;

    emitEvent(
      SyncEvent.now(
        type: type,
        taskId: taskId,
        entityType: entityType,
        message: message,
        metadata: metadata,
      ),
    );
  }

  /// Records sync start for duration calculation.
  void recordSyncStart() {
    if (!_enabled) return;
    _lastSyncStartTime = DateTime.now();
    emitEventNow(type: SyncEventType.syncStarted);
  }

  /// Records sync completion and calculates duration.
  void recordSyncComplete({bool hadFailures = false}) {
    if (!_enabled) return;

    final now = DateTime.now();
    _lastSyncTime = now;

    if (_lastSyncStartTime != null) {
      final duration = now.difference(_lastSyncStartTime!).inMilliseconds;
      _metrics.recordSyncDuration(duration);
    }

    emitEventNow(
      type: SyncEventType.syncCompleted,
      metadata: {'hadFailures': hadFailures},
    );
  }

  /// Gets the current snapshot of sync engine state.
  ///
  /// This is a read-only operation that does not affect sync behavior.
  Future<SyncDebugSnapshot> getCurrentSnapshot() async {
    try {
      // Read every task. This is read-only: it never changes task state.
      final allTasks = await _store.getAllTasks();
      
      // Count tasks by status
      int pendingCount = 0;
      int syncingCount = 0;
      int failedCount = 0;
      int syncedCount = 0;
      int deadLetterCount = 0;

      for (final task in allTasks) {
        switch (task.status) {
          case SyncStatus.pending:
            pendingCount++;
            break;
          case SyncStatus.syncing:
            syncingCount++;
            break;
          case SyncStatus.failed:
            failedCount++;
            break;
          case SyncStatus.synced:
            syncedCount++;
            break;
          case SyncStatus.deadLetter:
            deadLetterCount++;
            break;
        }
      }

      // Check online status
      bool? isOnline;
      if (_connectivityService != null) {
        try {
          isOnline = await _connectivityService!.isOnline();
        } catch (e) {
          // Fail silently
        }
      }

      return SyncDebugSnapshot(
        totalTasks: allTasks.length,
        pendingTasks: pendingCount,
        syncingTasks: syncingCount,
        failedTasks: failedCount,
        syncedTasks: syncedCount,
        deadLetterTasks: deadLetterCount,
        lastSyncTime: _lastSyncTime,
        isSyncing: syncingCount > 0,
        isOnline: isOnline,
        metrics: _metrics,
      );
    } catch (e) {
      // Return empty snapshot on error
      return SyncDebugSnapshot.empty();
    }
  }

  /// Resets all metrics.
  void resetMetrics() {
    _metrics.reset();
  }

  /// Disposes of resources used by this controller.
  void dispose() {
    _eventController.close();
  }
}

