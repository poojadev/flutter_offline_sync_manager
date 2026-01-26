import 'sync_metrics.dart';

/// Immutable snapshot of the current sync engine state.
///
/// This is a read-only view that does not affect sync behavior.
/// Useful for debugging and observability.
class SyncDebugSnapshot {
  /// Total number of tasks in the queue.
  final int totalTasks;

  /// Number of tasks pending sync.
  final int pendingTasks;

  /// Number of tasks currently syncing.
  final int syncingTasks;

  /// Number of tasks that failed (may be retried).
  final int failedTasks;

  /// Number of tasks successfully synced.
  final int syncedTasks;

  /// Timestamp of the last sync operation, if any.
  final DateTime? lastSyncTime;

  /// Whether a sync is currently in progress.
  final bool isSyncing;

  /// Whether the device is currently online.
  final bool? isOnline;

  /// Current sync metrics.
  final SyncMetrics metrics;

  /// Creates a [SyncDebugSnapshot] with the given state.
  const SyncDebugSnapshot({
    required this.totalTasks,
    required this.pendingTasks,
    required this.syncingTasks,
    required this.failedTasks,
    required this.syncedTasks,
    this.lastSyncTime,
    required this.isSyncing,
    this.isOnline,
    required this.metrics,
  });

  /// Creates an empty snapshot (no tasks, no sync in progress).
  factory SyncDebugSnapshot.empty() {
    return SyncDebugSnapshot(
      totalTasks: 0,
      pendingTasks: 0,
      syncingTasks: 0,
      failedTasks: 0,
      syncedTasks: 0,
      isSyncing: false,
      metrics: SyncMetrics(),
    );
  }

  @override
  String toString() {
    final buffer = StringBuffer('SyncDebugSnapshot(\n');
    buffer.writeln('  totalTasks: $totalTasks');
    buffer.writeln('  pendingTasks: $pendingTasks');
    buffer.writeln('  syncingTasks: $syncingTasks');
    buffer.writeln('  failedTasks: $failedTasks');
    buffer.writeln('  syncedTasks: $syncedTasks');
    if (lastSyncTime != null) {
      buffer.writeln('  lastSyncTime: $lastSyncTime');
    }
    buffer.writeln('  isSyncing: $isSyncing');
    if (isOnline != null) {
      buffer.writeln('  isOnline: $isOnline');
    }
    buffer.writeln('  metrics: $metrics');
    buffer.write(')');
    return buffer.toString();
  }

  /// Converts snapshot to a map for JSON export (debug only).
  ///
  /// This should only be used in debug mode.
  Map<String, dynamic> toMap() {
    return {
      'totalTasks': totalTasks,
      'pendingTasks': pendingTasks,
      'syncingTasks': syncingTasks,
      'failedTasks': failedTasks,
      'syncedTasks': syncedTasks,
      'lastSyncTime': lastSyncTime?.toIso8601String(),
      'isSyncing': isSyncing,
      'isOnline': isOnline,
      'metrics': metrics.toMap(),
    };
  }
}

