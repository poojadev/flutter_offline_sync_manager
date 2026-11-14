/// Priority of a sync task.
///
/// Higher-priority tasks are sent before lower-priority ones, regardless of
/// when they were enqueued. Within the same priority, tasks are sent oldest
/// first (FIFO).
///
/// Priority never breaks per-entity ordering: an update to an entity is
/// never sent before an older, unsynced create of that same entity.
enum SyncPriority {
  /// Background work that can wait (analytics, read receipts, caches).
  low,

  /// Default priority.
  normal,

  /// User-visible changes that should reach the server soon.
  high,

  /// Changes that must go first (payments, auth, account changes).
  critical,
}
