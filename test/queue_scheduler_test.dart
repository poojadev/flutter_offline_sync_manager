import 'package:flutter_offline_sync_manager/flutter_offline_sync_manager.dart';
import 'package:flutter_test/flutter_test.dart';

final t0 = DateTime(2026, 1, 1);

SyncTask task(
  String type,
  String id,
  SyncOperation op, {
  int minute = 0,
  SyncStatus status = SyncStatus.pending,
  SyncPriority priority = SyncPriority.normal,
  List<EntityRef> dependsOn = const [],
  DateTime? nextAttemptAt,
  int retryCount = 0,
}) =>
    SyncTask(
      entityType: type,
      entityId: id,
      operation: op,
      payload: const {},
      createdAt: t0.add(Duration(minutes: minute)),
      status: status,
      priority: priority,
      dependsOn: dependsOn,
      nextAttemptAt: nextAttemptAt,
      retryCount: retryCount,
    );

List<String> select(List<SyncTask> tasks,
        {int limit = 10, DateTime? now, bool ignoreBackoff = false}) =>
    QueueScheduler.selectBatch(tasks,
            now: now ?? t0.add(const Duration(hours: 1)),
            limit: limit,
            canRetry: (n) => n < 3,
            ignoreBackoff: ignoreBackoff)
        .map((t) => t.taskId)
        .toList();

void main() {
  group('QueueScheduler.selectBatch', () {
    test('orders by priority, then age', () {
      final ids = select([
        task('a', '1', SyncOperation.create,
            minute: 0, priority: SyncPriority.low),
        task('a', '2', SyncOperation.create, minute: 1),
        task('a', '3', SyncOperation.create,
            minute: 2, priority: SyncPriority.critical),
        task('a', '4', SyncOperation.create, minute: 3),
      ]);
      expect(ids, ['a_3_create', 'a_2_create', 'a_4_create', 'a_1_create']);
    });

    test('sends one task per entity, oldest first', () {
      final ids = select([
        task('n', '1', SyncOperation.update,
            minute: 1, priority: SyncPriority.critical),
        task('n', '1', SyncOperation.create, minute: 0),
      ]);
      expect(ids, ['n_1_create'],
          reason: 'priority never lets an update overtake its create');
    });

    test('an in-flight or dead-lettered head blocks the entity', () {
      expect(
          select([
            task('n', '1', SyncOperation.create, status: SyncStatus.syncing),
            task('n', '1', SyncOperation.update, minute: 1),
          ]),
          isEmpty);
      expect(
          select([
            task('n', '1', SyncOperation.create, status: SyncStatus.deadLetter),
            task('n', '1', SyncOperation.update, minute: 1),
          ]),
          isEmpty);
    });

    test('dependsOn waits for the dependency entity to be fully synced', () {
      final post = task('post', 'p1', SyncOperation.create);
      final comment = task('comment', 'c1', SyncOperation.create,
          minute: 1, dependsOn: const [EntityRef('post', 'p1')]);
      expect(select([post, comment]), ['post_p1_create']);
      expect(select([comment]), ['comment_c1_create']);
      expect(select([post..status = SyncStatus.synced, comment]),
          ['comment_c1_create']);
    });

    test('respects backoff unless ignored', () {
      final later = t0.add(const Duration(minutes: 30));
      final failed = task('n', '1', SyncOperation.update,
          status: SyncStatus.failed, retryCount: 1, nextAttemptAt: later);
      expect(select([failed], now: t0), isEmpty);
      expect(select([failed], now: later), ['n_1_update']);
      expect(select([failed], now: t0, ignoreBackoff: true), ['n_1_update']);
    });

    test('skips tasks without retry budget', () {
      expect(
          select([
            task('n', '1', SyncOperation.update,
                status: SyncStatus.failed, retryCount: 3)
          ]),
          isEmpty);
    });

    test('limits the batch size', () {
      final tasks = [
        for (var i = 0; i < 5; i++)
          task('n', '$i', SyncOperation.create, minute: i)
      ];
      expect(select(tasks, limit: 2), ['n_0_create', 'n_1_create']);
    });
  });

  test('entityStatus reports the most severe status', () {
    expect(QueueScheduler.entityStatus([]), EntitySyncStatus.synced);
    expect(
        QueueScheduler.entityStatus([
          task('n', '1', SyncOperation.create),
          task('n', '1', SyncOperation.update, status: SyncStatus.failed),
        ]),
        EntitySyncStatus.failed);
  });
}
