import 'package:flutter_offline_sync_manager/flutter_offline_sync_manager.dart';
import 'package:flutter_offline_sync_manager/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;
  late InMemorySyncStore store;
  late FakeSyncAdapter adapter;
  late FakeConnectivityService connectivity;
  final managers = <OfflineSyncManager>[];

  OfflineSyncManager build({
    SyncConfig config = const SyncConfig(),
    RetryPolicy? retryPolicy,
    ConflictDetector? detector,
  }) {
    final m = OfflineSyncManager(
      store: store,
      adapter: adapter,
      config: config,
      connectivityService: connectivity,
      retryPolicy: retryPolicy,
      conflictDetector: detector,
      clock: () => now,
    );
    managers.add(m);
    return m;
  }

  Future<void> put(OfflineSyncManager m, String id, SyncOperation op,
          [Map<String, dynamic> payload = const {},
          SyncPriority priority = SyncPriority.normal,
          List<EntityRef> dependsOn = const []]) =>
      m.enqueue(
          entityType: 'note',
          entityId: id,
          operation: op,
          payload: payload,
          priority: priority,
          dependsOn: dependsOn);

  setUp(() {
    now = DateTime(2026, 1, 1, 12);
    store = InMemorySyncStore();
    adapter = FakeSyncAdapter();
    connectivity = FakeConnectivityService();
  });

  tearDown(() {
    for (final m in managers) {
      m.dispose();
    }
    managers.clear();
  });

  test('drains the whole queue in one sync, batch by batch', () async {
    final m = build(config: const SyncConfig(batchSize: 2));
    for (var i = 0; i < 5; i++) {
      await put(m, '$i', SyncOperation.create, {'i': i});
    }
    final report = await m.sync();
    expect(adapter.batches.map((b) => b.length), [2, 2, 1]);
    expect(report.succeeded, 5);
    expect(report.batches, 3);
    expect(store.length, 0, reason: 'synced tasks are purged by default');
  });

  test('coalesces create + updates into one request', () async {
    final m = build();
    await put(m, 'n1', SyncOperation.create, {'title': 'a', 'body': 'x'});
    await put(m, 'n1', SyncOperation.update, {'title': 'b'});
    await put(m, 'n1', SyncOperation.update, {'body': 'y'});
    await m.sync();
    expect(adapter.sentTaskIds, ['note_n1_create']);
    expect(adapter.sentTasks.single.payload, {'title': 'b', 'body': 'y'});
  });

  test('create + delete before syncing sends nothing', () async {
    final m = build();
    await put(m, 'n1', SyncOperation.create, {'title': 'a'});
    await put(m, 'n1', SyncOperation.delete);
    await m.sync();
    expect(adapter.batches, isEmpty);
    expect(store.length, 0);
  });

  test('an edit made while a task is in flight is not lost', () async {
    final m = build();
    await put(m, 'n1', SyncOperation.update, {'v': 1});
    var first = true;
    adapter.handler = (batch) async {
      if (first) {
        first = false;
        // The user edits the note while the request is on the wire.
        await put(m, 'n1', SyncOperation.update, {'v': 2});
      }
      return SyncResult.allSuccess(batch.map((t) => t.taskId).toList());
    };
    await m.sync();
    expect(adapter.sentTasks.map((t) => t.payload['v']), [1, 2],
        reason: 'v2 must be sent instead of being marked synced by the v1 ack');
    expect(store.length, 0);
  });

  test('failed tasks wait for their backoff delay', () async {
    final m =
        build(retryPolicy: const RetryPolicy(baseDelay: Duration(seconds: 10)));
    await put(m, 'n1', SyncOperation.update);
    adapter.failNext(1, error: 'HTTP 503');

    final r1 = await m.sync();
    expect(r1.failed, 1);
    final failed = (await m.getTasks()).single;
    expect(failed.status, SyncStatus.failed);
    expect(failed.nextAttemptAt, now.add(const Duration(seconds: 10)));
    expect(m.state.nextRetryAt, failed.nextAttemptAt);

    await m.sync();
    expect(adapter.batches, hasLength(1), reason: 'still backing off');

    now = now.add(const Duration(seconds: 11));
    final r3 = await m.sync();
    expect(r3.succeeded, 1);
    expect(adapter.batches, hasLength(2));
  });

  test('sync(force: true) ignores backoff', () async {
    final m = build();
    await put(m, 'n1', SyncOperation.update);
    adapter.failNext(1);
    await m.sync();
    await m.sync(force: true);
    expect(adapter.batches, hasLength(2));
  });

  test('exhausted retries go to the dead-letter queue and can be revived',
      () async {
    final m = build(
        retryPolicy:
            const RetryPolicy(maxRetries: 2, baseDelay: Duration(seconds: 1)));
    await put(m, 'n1', SyncOperation.update, {'v': 1});
    adapter.failNext(2);

    await m.sync();
    now = now.add(const Duration(seconds: 5));
    final r2 = await m.sync();
    expect(r2.deadLettered, 1);

    final dead = await m.getDeadLetterTasks();
    expect(dead.single.retryCount, 2);
    expect(m.state.deadLetterCount, 1);
    expect(await m.getEntityStatus('note', 'n1'), EntitySyncStatus.deadLetter);

    expect(await m.retryDeadLetter(), 1);
    final r3 = await m.sync();
    expect(r3.succeeded, 1);
    expect(store.length, 0);
  });

  test('non-retryable errors are dead-lettered immediately', () async {
    final m = build();
    await put(m, 'n1', SyncOperation.create);
    await put(m, 'n2', SyncOperation.create);
    adapter.throwNext(1, const ValidationError('title is required'));

    final report = await m.sync();
    expect(report.deadLettered, 2);
    expect((await m.getDeadLetterTasks()).first.lastError, 'title is required');

    expect(await m.discardDeadLetters(), 2);
    expect(store.length, 0);
  });

  test('permanentFailureTaskIds from the adapter are honoured', () async {
    final m = build();
    await put(m, 'n1', SyncOperation.create);
    adapter.failNext(1, error: 'HTTP 422', permanent: true);
    final report = await m.sync();
    expect(report.deadLettered, 1);
    expect(report.failed, 0);
  });

  test('dependent tasks wait for their dependency', () async {
    final m = build();
    await m.enqueue(
      entityType: 'comment',
      entityId: 'c1',
      operation: SyncOperation.create,
      payload: const {},
      dependsOn: const [EntityRef('post', 'p1')],
    );
    await m.enqueue(
      entityType: 'post',
      entityId: 'p1',
      operation: SyncOperation.create,
      payload: const {},
    );
    adapter.failNext(1);

    await m.sync();
    expect(adapter.sentTaskIds, ['post_p1_create'],
        reason: 'comment is held back while its post is unsynced');
    expect(await m.getEntityStatus('comment', 'c1'), EntitySyncStatus.pending);

    await m.sync(force: true);
    expect(adapter.sentTaskIds,
        ['post_p1_create', 'post_p1_create', 'comment_c1_create']);
  });

  test('higher-priority tasks are sent first', () async {
    final m = build(config: const SyncConfig(batchSize: 1));
    await put(m, 'low', SyncOperation.create, {}, SyncPriority.low);
    await put(m, 'normal', SyncOperation.create);
    await put(m, 'critical', SyncOperation.create, {}, SyncPriority.critical);
    await m.sync();
    expect(adapter.sentTaskIds,
        ['note_critical_create', 'note_normal_create', 'note_low_create']);
  });

  test('conflict loops are bounded by the retry budget', () async {
    final m = build(
      config: const SyncConfig(conflictStrategy: ConflictStrategy.clientWins),
      retryPolicy: const RetryPolicy(maxRetries: 3),
    );
    await put(m, 'n1', SyncOperation.update, {'v': 1});
    adapter.handler = (batch) => SyncResult(
          successTaskIds: const {},
          failedTaskErrors: {for (final t in batch) t.taskId: 'HTTP 409'},
          serverData: {
            for (final t in batch) t.taskId: {'v': 0, 'conflict': true}
          },
        );

    final report = await m.sync();
    expect(adapter.batches, hasLength(3));
    expect(report.conflicts, 3);
    expect(report.deadLettered, 1);
  });

  test('serverWins conflict resolution completes the task', () async {
    final m = build(
        config:
            const SyncConfig(conflictStrategy: ConflictStrategy.serverWins));
    await put(m, 'n1', SyncOperation.update, {'v': 1});
    adapter.enqueueResponse((batch) => SyncResult(
          successTaskIds: const {},
          failedTaskErrors: {batch.single.taskId: 'conflict'},
          serverData: {
            batch.single.taskId: {'v': 9}
          },
        ));
    final report = await m.sync();
    expect(report.conflicts, 1);
    expect(store.length, 0);
  });

  test('circuit breaker opens after repeated failures', () async {
    final m = build(
      config: const SyncConfig(
        circuitBreaker: CircuitBreakerConfig(
            failureThreshold: 2, cooldown: Duration(minutes: 5)),
      ),
      retryPolicy: const RetryPolicy(baseDelay: Duration(seconds: 1)),
    );
    await put(m, 'n1', SyncOperation.update);
    adapter.failNext(2, error: 'HTTP 503');

    await m.sync();
    now = now.add(const Duration(seconds: 10));
    await m.sync();
    expect(m.state.phase, SyncPhase.circuitOpen);
    expect(m.circuitState, CircuitState.open);

    now = now.add(const Duration(seconds: 10));
    final skipped = await m.sync();
    expect(skipped.skippedReason, SyncSkipReason.circuitOpen);
    expect(adapter.batches, hasLength(2));

    now = now.add(const Duration(minutes: 5));
    final trial = await m.sync();
    expect(trial.succeeded, 1);
    expect(m.circuitState, CircuitState.closed);
    expect(m.state.phase, SyncPhase.idle);
  });

  test('skips when offline', () async {
    final m = build();
    await put(m, 'n1', SyncOperation.update);
    connectivity.online = false;
    final report = await m.sync();
    expect(report.skippedReason, SyncSkipReason.offline);
    expect(m.state.phase, SyncPhase.offline);
    expect(adapter.batches, isEmpty);
  });

  test('pause skips syncing until resumed; force overrides', () async {
    final m = build();
    await put(m, 'n1', SyncOperation.update);
    m.pause();
    expect((await m.sync()).skippedReason, SyncSkipReason.paused);
    expect(m.state.phase, SyncPhase.paused);
    expect((await m.sync(force: true)).succeeded, 1);
    m.resume();
    expect(m.state.phase, SyncPhase.idle);
  });

  test('tasks past their time-to-live are dead-lettered', () async {
    final m =
        build(config: const SyncConfig(taskTimeToLive: Duration(hours: 1)));
    await put(m, 'n1', SyncOperation.update);
    now = now.add(const Duration(hours: 2));
    final report = await m.sync();
    expect(report.deadLettered, 1);
    expect(adapter.batches, isEmpty);
    expect(
        (await m.getDeadLetterTasks()).single.lastError, contains('Expired'));
  });

  test('synced tasks are kept for the retention window', () async {
    final m = build(
        config: const SyncConfig(syncedTaskRetention: Duration(minutes: 10)));
    await put(m, 'n1', SyncOperation.update);
    await m.sync();
    expect((await m.getTasks()).single.status, SyncStatus.synced);
    now = now.add(const Duration(minutes: 11));
    await m.sync();
    expect(store.length, 0);
  });

  test('concurrent sync calls share one run', () async {
    adapter.latency = const Duration(milliseconds: 20);
    final m = build();
    await put(m, 'n1', SyncOperation.update);
    final a = m.sync();
    final b = m.sync();
    expect(m.isSyncing, isTrue);
    final results = await Future.wait([a, b]);
    expect(identical(results[0], results[1]), isTrue);
    expect(adapter.batches, hasLength(1));
  });

  test('watchEntity reports pending → syncing → synced', () async {
    adapter.latency = const Duration(milliseconds: 5);
    final m = build();
    final statuses = <EntitySyncStatus>[];
    final sub = m.watchEntity('note', 'n1').listen(statuses.add);
    await pumpEventQueue();

    await put(m, 'n1', SyncOperation.update);
    await m.sync();
    await pumpEventQueue();
    await sub.cancel();

    expect(statuses, [
      EntitySyncStatus.synced,
      EntitySyncStatus.pending,
      EntitySyncStatus.syncing,
      EntitySyncStatus.synced,
    ]);
  });

  test('stateStream emits current state first, then updates', () async {
    final m = build();
    await put(m, 'n1', SyncOperation.update);
    final states = <SyncState>[];
    final sub = m.stateStream.listen(states.add);
    await pumpEventQueue();
    expect(states.first.pendingCount, 1);
    expect(states.first.hasUnsyncedChanges, isTrue);

    await m.sync();
    await pumpEventQueue();
    await sub.cancel();
    expect(states.last.pendingCount, 0);
    expect(states.last.lastReport?.succeeded, 1);
    expect(states.map((s) => s.phase), contains(SyncPhase.syncing));
  });

  test('auto-sync retries automatically after backoff', () async {
    final m = OfflineSyncManager(
      store: store,
      adapter: adapter,
      connectivityService: connectivity,
      retryPolicy: const RetryPolicy(baseDelay: Duration(milliseconds: 20)),
    );
    managers.add(m);
    await m.enqueue(
        entityType: 'note',
        entityId: 'n1',
        operation: SyncOperation.update,
        payload: const {});
    adapter.failNext(1);
    m.enableAutoSync();

    // Initial auto-sync fails, then the scheduled retry succeeds.
    for (var i = 0; i < 50 && store.length > 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(adapter.batches, hasLength(2));
    expect(store.length, 0);
  });

  test('sync-on-enqueue debounces bursts of edits', () async {
    final m = OfflineSyncManager(
      store: store,
      adapter: adapter,
      connectivityService: connectivity,
      config:
          const SyncConfig(syncOnEnqueueDebounce: Duration(milliseconds: 30)),
    );
    managers.add(m);
    m.enableAutoSync();
    await pumpEventQueue();
    for (var i = 0; i < 3; i++) {
      await m.enqueue(
          entityType: 'note',
          entityId: 'n1',
          operation: SyncOperation.update,
          payload: {'v': i});
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(adapter.batches, hasLength(1));
    expect(adapter.sentTasks.single.payload, {'v': 2});
  });

  test('tasks left syncing by a crash are recovered', () async {
    await store.saveTask(SyncTask(
      entityType: 'note',
      entityId: 'n1',
      operation: SyncOperation.update,
      payload: const {},
      status: SyncStatus.syncing,
    ));
    final m = build();
    expect((await m.sync()).succeeded, 1);
  });

  test('debug controller sees new event types', () async {
    final debug = SyncDebugController(store: store)..enable();
    final m = OfflineSyncManager(
        store: store,
        adapter: adapter,
        debugController: debug,
        clock: () => now);
    managers.add(m);
    final events = <SyncEventType>[];
    final sub = debug.events.listen((e) => events.add(e.type));

    await put(m, 'n1', SyncOperation.create);
    await put(m, 'n1', SyncOperation.update);
    adapter.failNext(1, permanent: true);
    await m.sync();
    await pumpEventQueue();
    await sub.cancel();

    expect(
        events,
        containsAll([
          SyncEventType.taskCoalesced,
          SyncEventType.taskDeadLettered,
        ]));
    final snapshot = await m.getDebugSnapshot();
    expect(snapshot!.deadLetterTasks, 1);
    expect(debug.metrics.totalTasksCoalesced, 1);
    debug.dispose();
  });
}
