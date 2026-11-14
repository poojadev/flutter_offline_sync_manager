import '../core/sync_status.dart';
import '../core/sync_task.dart';
import 'sync_store.dart';

/// A non-persistent [SyncStore] that keeps tasks in memory.
///
/// Useful for tests, previews, and web builds where persistence isn't
/// required. Tasks are copied on the way in and out, so callers can never
/// mutate stored state by accident (mirroring a real database).
class InMemorySyncStore implements SyncStore {
  final Map<String, SyncTask> _tasks = {};

  /// Number of tasks currently stored.
  int get length => _tasks.length;

  @override
  Future<void> saveTask(SyncTask task) async {
    _tasks[task.taskId] = task.copyWith();
  }

  @override
  Future<void> updateTask(SyncTask task) => saveTask(task);

  @override
  Future<SyncTask?> getTask(String taskId) async => _tasks[taskId]?.copyWith();

  @override
  Future<List<SyncTask>> getAllTasks() async =>
      _tasks.values.map((t) => t.copyWith()).toList();

  @override
  Future<void> deleteTask(String taskId) async {
    _tasks.remove(taskId);
  }

  @override
  Future<List<SyncTask>> getPendingTasks(int limit) async {
    final tasks = _tasks.values
        .where((t) =>
            t.status == SyncStatus.pending ||
            t.status == SyncStatus.failed ||
            t.status == SyncStatus.syncing)
        .map((t) => t.copyWith())
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return tasks.take(limit).toList();
  }

  @override
  Future<void> markSyncing(String taskId) async =>
      _tasks[taskId]?.updateStatus(SyncStatus.syncing);

  @override
  Future<void> markSynced(String taskId) async =>
      _tasks[taskId]?.updateStatus(SyncStatus.synced);

  @override
  Future<void> markFailed(String taskId, String error) async =>
      _tasks[taskId]?.incrementRetry(error);

  /// Removes every task.
  void clear() => _tasks.clear();
}
