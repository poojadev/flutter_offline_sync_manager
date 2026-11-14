import 'dart:collection';

/// Aggregator for sync metrics and statistics.
///
/// Tracks counters and timers for observability and debugging.
/// Metrics are lightweight and do not persist by default.
class SyncMetrics {
  /// Total number of tasks enqueued.
  int totalTasksEnqueued = 0;

  /// Total number of tasks successfully synced.
  int totalTasksSynced = 0;

  /// Total number of tasks that failed (including retries).
  int totalTasksFailed = 0;

  /// Total number of retry attempts.
  int totalRetries = 0;

  /// Total number of conflicts detected.
  int totalConflictsDetected = 0;

  /// Total number of conflicts resolved.
  int totalConflictsResolved = 0;

  /// Total number of changes merged into already-queued tasks.
  int totalTasksCoalesced = 0;

  /// Total number of tasks moved to the dead-letter queue.
  int totalTasksDeadLettered = 0;

  /// Duration of the last sync operation in milliseconds.
  int? lastSyncDuration;

  /// List of recent sync durations for calculating average.
  ///
  /// Limited to last 100 syncs to prevent memory bloat.
  final Queue<int> _recentSyncDurations = Queue<int>();

  /// Maximum number of recent sync durations to keep.
  static const int _maxRecentDurations = 100;

  /// Creates a [SyncMetrics] instance.
  SyncMetrics();

  /// Increments the enqueued tasks counter.
  void incrementEnqueued() {
    totalTasksEnqueued++;
  }

  /// Increments the synced tasks counter.
  void incrementSynced() {
    totalTasksSynced++;
  }

  /// Increments the failed tasks counter.
  void incrementFailed() {
    totalTasksFailed++;
  }

  /// Increments the retries counter.
  void incrementRetries() {
    totalRetries++;
  }

  /// Increments the conflicts detected counter.
  void incrementConflictsDetected() {
    totalConflictsDetected++;
  }

  /// Increments the conflicts resolved counter.
  void incrementConflictsResolved() {
    totalConflictsResolved++;
  }

  /// Increments the coalesced tasks counter.
  void incrementCoalesced() {
    totalTasksCoalesced++;
  }

  /// Increments the dead-lettered tasks counter.
  void incrementDeadLettered() {
    totalTasksDeadLettered++;
  }

  /// Records a sync duration.
  ///
  /// [durationMs] - Duration of the sync in milliseconds.
  void recordSyncDuration(int durationMs) {
    lastSyncDuration = durationMs;
    _recentSyncDurations.add(durationMs);

    // Limit queue size to prevent memory bloat
    if (_recentSyncDurations.length > _maxRecentDurations) {
      _recentSyncDurations.removeFirst();
    }
  }

  /// Gets the average sync duration in milliseconds.
  ///
  /// Returns null if no syncs have been recorded.
  int? get averageSyncDuration {
    if (_recentSyncDurations.isEmpty) {
      return null;
    }

    final sum = _recentSyncDurations.fold<int>(
      0,
      (acc, duration) => acc + duration,
    );
    return (sum / _recentSyncDurations.length).round();
  }

  /// Gets the number of syncs used for average calculation.
  int get syncCountForAverage => _recentSyncDurations.length;

  /// Resets all metrics to zero.
  void reset() {
    totalTasksEnqueued = 0;
    totalTasksSynced = 0;
    totalTasksFailed = 0;
    totalRetries = 0;
    totalConflictsDetected = 0;
    totalConflictsResolved = 0;
    totalTasksCoalesced = 0;
    totalTasksDeadLettered = 0;
    lastSyncDuration = null;
    _recentSyncDurations.clear();
  }

  /// Converts metrics to a map for JSON export (debug only).
  ///
  /// This should only be used in debug mode.
  Map<String, dynamic> toMap() {
    return {
      'totalTasksEnqueued': totalTasksEnqueued,
      'totalTasksSynced': totalTasksSynced,
      'totalTasksFailed': totalTasksFailed,
      'totalRetries': totalRetries,
      'totalConflictsDetected': totalConflictsDetected,
      'totalConflictsResolved': totalConflictsResolved,
      'totalTasksCoalesced': totalTasksCoalesced,
      'totalTasksDeadLettered': totalTasksDeadLettered,
      'lastSyncDuration': lastSyncDuration,
      'averageSyncDuration': averageSyncDuration,
      'syncCountForAverage': syncCountForAverage,
    };
  }

  @override
  String toString() {
    return 'SyncMetrics('
        'enqueued: $totalTasksEnqueued, '
        'synced: $totalTasksSynced, '
        'failed: $totalTasksFailed, '
        'retries: $totalRetries, '
        'conflicts: $totalConflictsDetected/$totalConflictsResolved, '
        'coalesced: $totalTasksCoalesced, '
        'deadLettered: $totalTasksDeadLettered, '
        'lastDuration: ${lastSyncDuration}ms, '
        'avgDuration: ${averageSyncDuration}ms'
        ')';
  }
}
