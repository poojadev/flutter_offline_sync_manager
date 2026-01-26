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
}

