/// Represents the current status of a sync task.
enum SyncStatus {
  /// Task is queued and waiting to be synced.
  pending,

  /// Task is currently being synced to the server.
  syncing,

  /// Task sync failed and may be retried.
  failed,

  /// Task has been successfully synced to the server.
  synced,
}

