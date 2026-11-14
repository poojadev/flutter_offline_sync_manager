/// Represents the current status of a sync task.
enum SyncStatus {
  /// Task is queued and waiting to be synced.
  pending,

  /// Task is currently being synced to the server.
  syncing,

  /// Task sync failed and will be retried after its backoff delay.
  failed,

  /// Task has been successfully synced to the server.
  ///
  /// Synced tasks are only kept when [SyncConfig.syncedTaskRetention] is
  /// greater than zero; by default they are removed as soon as the server
  /// confirms them.
  synced,

  /// Task failed permanently and will not be retried automatically.
  ///
  /// This happens when retries are exhausted, the server rejects the task as
  /// non-retryable, conflict resolution aborts, or the task outlives
  /// [SyncConfig.taskTimeToLive]. Dead-lettered tasks are never deleted
  /// automatically: inspect them with
  /// [OfflineSyncManager.getDeadLetterTasks] and either retry them with
  /// [OfflineSyncManager.retryDeadLetter] or drop them with
  /// [OfflineSyncManager.discardTask].
  deadLetter,
}
