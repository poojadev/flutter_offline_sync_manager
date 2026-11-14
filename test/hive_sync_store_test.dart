import 'dart:io';
import 'package:flutter_offline_sync_manager/flutter_offline_sync_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hive_sync_store_test');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  SyncTask task(String id, int minute) => SyncTask(
        entityType: 'note',
        entityId: id,
        operation: SyncOperation.update,
        payload: {'id': id},
        createdAt: DateTime(2026, 1, 1, 0, minute),
        priority: SyncPriority.high,
        dependsOn: const [EntityRef('post', 'p1')],
        revision: 3,
        nextAttemptAt: DateTime(2026, 1, 2),
      );

  test('persists new fields across restarts (with encryption)', () async {
    final cipher = HiveAesCipher(List<int>.generate(32, (i) => i));
    var store = HiveSyncStore(boxName: 'q', encryptionCipher: cipher);
    await store.saveTask(task('a', 0));
    await store.close();

    store = HiveSyncStore(boxName: 'q', encryptionCipher: cipher);
    final read = (await store.getTask('note_a_update'))!;
    expect(read.priority, SyncPriority.high);
    expect(read.dependsOn, const [EntityRef('post', 'p1')]);
    expect(read.revision, 3);
    expect(read.nextAttemptAt, DateTime(2026, 1, 2));
    expect(read.payload, {'id': 'a'});
  });

  test('getPendingTasks sorts before applying the limit', () async {
    final store = HiveSyncStore(boxName: 'sorted');
    await store.saveTask(task('late', 30));
    await store.saveTask(task('early', 0));
    await store.saveTask(task('mid', 10));
    final tasks = await store.getPendingTasks(2);
    expect(tasks.map((t) => t.entityId), ['early', 'mid']);
  });

  test('returned tasks are detached copies', () async {
    final store = HiveSyncStore(boxName: 'copies');
    await store.saveTask(task('a', 0));
    final copy = (await store.getTask('note_a_update'))!;
    copy.status = SyncStatus.deadLetter;
    expect((await store.getTask('note_a_update'))!.status, SyncStatus.pending);
    await store.deleteTask('note_a_update');
    expect(await store.getAllTasks(), isEmpty);
  });
}
