import '../core/sync_task.dart';

/// Abstract interface for persisting and managing sync tasks.
///
/// This abstraction allows for different storage implementations
/// (Hive, SQLite, etc.) without coupling the manager to a specific solution.
abstract class SyncStore {
  /// Saves or updates a sync task.
  ///
  /// If a task with the same [taskId] already exists, it should be overwritten.
  /// This method must be idempotent and crash-safe.
  Future<void> saveTask(SyncTask task);

  /// Updates an existing sync task.
  ///
  /// This method must be idempotent and crash-safe.
  Future<void> updateTask(SyncTask task);

  /// Retrieves pending tasks that are ready to be synced.
  ///
  /// Returns tasks with status [SyncStatus.pending] or [SyncStatus.failed]
  /// that have not exceeded the maximum retry count.
  /// Results are limited to [limit] tasks.
  Future<List<SyncTask>> getPendingTasks(int limit);

  /// Marks a task as currently being synced.
  ///
  /// This prevents the same task from being synced multiple times in parallel.
  /// Must be idempotent and crash-safe.
  Future<void> markSyncing(String taskId);

  /// Marks a task as successfully synced.
  ///
  /// This should only be called after receiving explicit server confirmation.
  /// Must be idempotent and crash-safe.
  Future<void> markSynced(String taskId);

  /// Marks a task as failed and increments its retry count.
  ///
  /// The [error] message should describe why the sync failed.
  /// Must be idempotent and crash-safe.
  Future<void> markFailed(String taskId, String error);
}

