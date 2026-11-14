/// Why a sync call did not run.
enum SyncSkipReason {
  /// The device was offline.
  offline,

  /// Syncing is paused via [OfflineSyncManager.pause].
  paused,

  /// The circuit breaker is open.
  circuitOpen,
}

/// Summary of a single [OfflineSyncManager.sync] call.
class SyncReport {
  /// Number of batches sent to the adapter.
  final int batches;

  /// Number of tasks sent to the adapter (a task retried within the same
  /// sync call is counted each time).
  final int attempted;

  /// Tasks confirmed by the server.
  final int succeeded;

  /// Tasks that failed and will be retried.
  final int failed;

  /// Conflicts detected (and handed to the conflict resolver).
  final int conflicts;

  /// Tasks moved to the dead-letter queue during this sync.
  final int deadLettered;

  /// Set when the sync did not run at all.
  final SyncSkipReason? skippedReason;

  /// How long the sync took.
  final Duration duration;

  /// Creates a [SyncReport].
  const SyncReport({
    this.batches = 0,
    this.attempted = 0,
    this.succeeded = 0,
    this.failed = 0,
    this.conflicts = 0,
    this.deadLettered = 0,
    this.skippedReason,
    this.duration = Duration.zero,
  });

  /// A report for a sync that was skipped.
  const SyncReport.skipped(SyncSkipReason reason) : this(skippedReason: reason);

  /// Whether the sync was skipped.
  bool get wasSkipped => skippedReason != null;

  /// Whether every attempted task succeeded.
  bool get isCleanRun => !wasSkipped && failed == 0 && deadLettered == 0;

  @override
  String toString() => wasSkipped
      ? 'SyncReport(skipped: ${skippedReason!.name})'
      : 'SyncReport(batches: $batches, attempted: $attempted, '
          'succeeded: $succeeded, failed: $failed, conflicts: $conflicts, '
          'deadLettered: $deadLettered, ${duration.inMilliseconds}ms)';
}
