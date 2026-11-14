import 'queue_compactor.dart';
import 'sync_state.dart';
import 'sync_status.dart';
import 'sync_task.dart';

/// Decides which tasks are ready to be sent.
///
/// Rules, in order:
/// 1. **Per-entity FIFO** – only the oldest outstanding task of an entity
///    can be sent. If it is in flight or dead-lettered, the entity is
///    blocked, so an update never overtakes the create it depends on.
/// 2. **Retry budget** – tasks that used up their retries are skipped.
/// 3. **Backoff** – failed tasks wait until their `nextAttemptAt`.
/// 4. **Dependencies** – a task waits until every entity in its `dependsOn`
///    list has no outstanding tasks.
/// 5. **Priority** – ready tasks are sent highest priority first, then
///    oldest first.
class QueueScheduler {
  const QueueScheduler._();

  /// Selects up to [limit] tasks to send now.
  static List<SyncTask> selectBatch(
    Iterable<SyncTask> allTasks, {
    required DateTime now,
    required int limit,
    required bool Function(int retryCount) canRetry,
    bool ignoreBackoff = false,
  }) {
    final outstanding = allTasks.where((t) => t.isOutstanding).toList()
      ..sort(QueueCompactor.compareQueueOrder);

    final outstandingEntities = <String>{};
    final headByEntity = <String, SyncTask>{};
    for (final task in outstanding) {
      outstandingEntities.add(task.entityKey);
      headByEntity.putIfAbsent(task.entityKey, () => task);
    }

    final ready = <SyncTask>[];
    for (final task in headByEntity.values) {
      if (task.status != SyncStatus.pending &&
          task.status != SyncStatus.failed) {
        continue;
      }
      if (!canRetry(task.retryCount)) continue;
      final next = task.nextAttemptAt;
      if (!ignoreBackoff && next != null && next.isAfter(now)) continue;
      final blocked = task.dependsOn.any(
        (dep) => dep.key != task.entityKey && outstandingEntities.contains(dep.key),
      );
      if (blocked) continue;
      ready.add(task);
    }

    ready.sort((a, b) {
      final byPriority = b.priority.index.compareTo(a.priority.index);
      return byPriority != 0 ? byPriority : QueueCompactor.compareQueueOrder(a, b);
    });
    return ready.take(limit).toList();
  }

  /// Aggregated status of one entity, from its outstanding tasks.
  static EntitySyncStatus entityStatus(Iterable<SyncTask> tasksOfEntity) {
    var result = EntitySyncStatus.synced;
    for (final task in tasksOfEntity) {
      final status = switch (task.status) {
        SyncStatus.synced => EntitySyncStatus.synced,
        SyncStatus.pending => EntitySyncStatus.pending,
        SyncStatus.syncing => EntitySyncStatus.syncing,
        SyncStatus.failed => EntitySyncStatus.failed,
        SyncStatus.deadLetter => EntitySyncStatus.deadLetter,
      };
      // Enum order doubles as severity: synced < pending < syncing < failed < deadLetter.
      if (status.index > result.index) result = status;
    }
    return result;
  }
}
