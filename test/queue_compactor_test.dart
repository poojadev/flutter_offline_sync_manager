import 'package:flutter_offline_sync_manager/flutter_offline_sync_manager.dart';
import 'package:flutter_test/flutter_test.dart';

SyncTask task(
  SyncOperation op,
  Map<String, dynamic> payload, {
  SyncStatus status = SyncStatus.pending,
  int retryCount = 0,
  int minute = 0,
  String id = 'n1',
  SyncPriority priority = SyncPriority.normal,
}) =>
    SyncTask(
      entityType: 'note',
      entityId: id,
      operation: op,
      payload: payload,
      status: status,
      retryCount: retryCount,
      createdAt: DateTime(2026, 1, 1, 0, minute),
      priority: priority,
    );

void main() {
  group('QueueCompactor', () {
    test('create + update merges into a single create', () {
      final prev = task(SyncOperation.create, {'title': 'a', 'body': 'x'});
      final plan = QueueCompactor.plan(
        existing: [prev],
        incoming: task(SyncOperation.update, {'title': 'b'}, minute: 1),
      );
      expect(plan.kind, CompactionKind.merged);
      expect(plan.save!.operation, SyncOperation.create);
      expect(plan.save!.payload, {'title': 'b', 'body': 'x'});
      expect(plan.save!.createdAt, prev.createdAt, reason: 'keeps queue position');
      expect(plan.save!.revision, prev.revision + 1);
      expect(plan.remove, isEmpty, reason: 'same taskId is overwritten');
    });

    test('update + upsert becomes upsert and drops the old task id', () {
      final plan = QueueCompactor.plan(
        existing: [task(SyncOperation.update, {'a': 1})],
        incoming: task(SyncOperation.upsert, {'b': 2}, minute: 1),
      );
      expect(plan.save!.operation, SyncOperation.upsert);
      expect(plan.save!.payload, {'a': 1, 'b': 2});
      expect(plan.remove, ['note_n1_update']);
    });

    test('update + delete becomes a delete', () {
      final plan = QueueCompactor.plan(
        existing: [task(SyncOperation.update, {'a': 1})],
        incoming: task(SyncOperation.delete, {}, minute: 1),
      );
      expect(plan.kind, CompactionKind.merged);
      expect(plan.save!.operation, SyncOperation.delete);
      expect(plan.remove, ['note_n1_update']);
    });

    test('create + delete of a never-sent entity annihilates', () {
      final plan = QueueCompactor.plan(
        existing: [task(SyncOperation.create, {'a': 1})],
        incoming: task(SyncOperation.delete, {}, minute: 1),
      );
      expect(plan.kind, CompactionKind.annihilated);
      expect(plan.save, isNull);
      expect(plan.remove, ['note_n1_create']);
    });

    test('create that was attempted + delete still sends the delete', () {
      final plan = QueueCompactor.plan(
        existing: [
          task(SyncOperation.create, {'a': 1},
              status: SyncStatus.failed, retryCount: 1)
        ],
        incoming: task(SyncOperation.delete, {}, minute: 1),
      );
      expect(plan.kind, CompactionKind.merged);
      expect(plan.save!.operation, SyncOperation.delete);
    });

    test('never merges into an in-flight task', () {
      final plan = QueueCompactor.plan(
        existing: [
          task(SyncOperation.create, {'a': 1}, status: SyncStatus.syncing)
        ],
        incoming: task(SyncOperation.update, {'a': 2}, minute: 1),
      );
      expect(plan.kind, CompactionKind.appended);
      expect(plan.save!.operation, SyncOperation.update);
    });

    test('same-id overwrite of an in-flight task bumps the revision', () {
      final inFlight = task(SyncOperation.update, {'a': 1},
          status: SyncStatus.syncing);
      final plan = QueueCompactor.plan(
        existing: [inFlight],
        incoming: task(SyncOperation.update, {'a': 2}, minute: 5),
      );
      expect(plan.kind, CompactionKind.replaced);
      expect(plan.save!.revision, inFlight.revision + 1);
      expect(plan.save!.status, SyncStatus.pending);
      expect(plan.save!.createdAt, inFlight.createdAt);
    });

    test('merging keeps the highest priority', () {
      final plan = QueueCompactor.plan(
        existing: [
          task(SyncOperation.update, {'a': 1}, priority: SyncPriority.high)
        ],
        incoming: task(SyncOperation.update, {'a': 2}, minute: 1),
      );
      expect(plan.save!.priority, SyncPriority.high);
    });

    test('coalesce: false keeps separate tasks', () {
      final plan = QueueCompactor.plan(
        existing: [task(SyncOperation.create, {'a': 1})],
        incoming: task(SyncOperation.update, {'a': 2}, minute: 1),
        coalesce: false,
      );
      expect(plan.kind, CompactionKind.appended);
      expect(plan.save!.operation, SyncOperation.update);
    });
  });
}
