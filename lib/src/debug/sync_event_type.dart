/// Types of sync events that can be emitted for debugging and observability.
///
/// These events are diagnostic only and do not affect sync behavior.
enum SyncEventType {
  /// A task was enqueued for sync.
  enqueue,

  /// A sync operation started.
  syncStarted,

  /// A sync operation completed (successfully or with failures).
  syncCompleted,

  /// A task was successfully synced to the server.
  taskSucceeded,

  /// A task failed to sync (may be retried).
  taskFailed,

  /// A retry was scheduled for a failed task.
  retryScheduled,

  /// A conflict was detected between local and server data.
  conflictDetected,

  /// A conflict was resolved using a resolution strategy.
  conflictResolved,

  /// Background sync was triggered by the OS.
  backgroundSyncTriggered,

  /// Sync was skipped because device is offline.
  skippedOffline,

  /// A change was merged into an already-queued task for the same entity.
  taskCoalesced,

  /// A create and delete cancelled out, so nothing was sent.
  taskAnnihilated,

  /// A task was moved to the dead-letter queue.
  taskDeadLettered,

  /// A dead-lettered task was put back into the queue.
  taskRevived,

  /// The circuit breaker opened after repeated failures.
  circuitOpened,

  /// The circuit breaker closed after a successful sync.
  circuitClosed,

  /// Syncing was paused.
  paused,

  /// Syncing was resumed.
  resumed,
}
