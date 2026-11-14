import 'sync_report.dart';

/// What the sync engine is doing right now.
enum SyncPhase {
  /// Nothing in progress.
  idle,

  /// A sync is in progress.
  syncing,

  /// The last sync attempt found the device offline.
  offline,

  /// Syncing was paused with [OfflineSyncManager.pause].
  paused,

  /// The circuit breaker is open after repeated failures.
  circuitOpen,
}

/// Sync status of a single entity, derived from its outstanding tasks.
///
/// Useful for "pending upload" badges and similar UI.
enum EntitySyncStatus {
  /// No outstanding tasks: the server has every local change.
  synced,

  /// Changes are queued and waiting to be sent.
  pending,

  /// Changes are being sent right now.
  syncing,

  /// The last attempt failed; a retry is scheduled.
  failed,

  /// Changes failed permanently and need attention.
  deadLetter,
}

/// Immutable, UI-friendly view of the sync engine.
///
/// Available through [OfflineSyncManager.state] and
/// [OfflineSyncManager.stateStream], independently of debug mode.
class SyncState {
  /// What the engine is doing.
  final SyncPhase phase;

  /// Tasks waiting to be sent for the first time.
  final int pendingCount;

  /// Tasks currently in flight.
  final int syncingCount;

  /// Tasks waiting for a retry after a failure.
  final int failedCount;

  /// Tasks that failed permanently.
  final int deadLetterCount;

  /// When the last sync finished, if any.
  final DateTime? lastSyncAt;

  /// Earliest scheduled retry among failed tasks, if any.
  final DateTime? nextRetryAt;

  /// Report of the last completed sync, if any.
  final SyncReport? lastReport;

  /// Creates a [SyncState].
  const SyncState({
    required this.phase,
    this.pendingCount = 0,
    this.syncingCount = 0,
    this.failedCount = 0,
    this.deadLetterCount = 0,
    this.lastSyncAt,
    this.nextRetryAt,
    this.lastReport,
  });

  /// Initial state before anything has been loaded.
  static const SyncState initial = SyncState(phase: SyncPhase.idle);

  /// Tasks that will still be sent automatically.
  int get outstandingCount => pendingCount + syncingCount + failedCount;

  /// Whether there are local changes the server does not have yet,
  /// including dead-lettered ones.
  bool get hasUnsyncedChanges => outstandingCount + deadLetterCount > 0;

  /// Returns a copy with the given fields replaced.
  SyncState copyWith({
    SyncPhase? phase,
    int? pendingCount,
    int? syncingCount,
    int? failedCount,
    int? deadLetterCount,
    DateTime? lastSyncAt,
    DateTime? nextRetryAt,
    bool clearNextRetryAt = false,
    SyncReport? lastReport,
  }) {
    return SyncState(
      phase: phase ?? this.phase,
      pendingCount: pendingCount ?? this.pendingCount,
      syncingCount: syncingCount ?? this.syncingCount,
      failedCount: failedCount ?? this.failedCount,
      deadLetterCount: deadLetterCount ?? this.deadLetterCount,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      nextRetryAt: clearNextRetryAt ? null : (nextRetryAt ?? this.nextRetryAt),
      lastReport: lastReport ?? this.lastReport,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SyncState &&
      other.phase == phase &&
      other.pendingCount == pendingCount &&
      other.syncingCount == syncingCount &&
      other.failedCount == failedCount &&
      other.deadLetterCount == deadLetterCount &&
      other.lastSyncAt == lastSyncAt &&
      other.nextRetryAt == nextRetryAt &&
      identical(other.lastReport, lastReport);

  @override
  int get hashCode => Object.hash(phase, pendingCount, syncingCount,
      failedCount, deadLetterCount, lastSyncAt, nextRetryAt, lastReport);

  @override
  String toString() => 'SyncState(${phase.name}, pending: $pendingCount, '
      'syncing: $syncingCount, failed: $failedCount, '
      'deadLetter: $deadLetterCount, nextRetryAt: $nextRetryAt)';
}
