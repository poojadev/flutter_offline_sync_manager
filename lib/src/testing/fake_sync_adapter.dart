import 'dart:async';
import '../adapter/sync_adapter.dart';
import '../core/sync_result.dart';
import '../core/sync_task.dart';

/// Decides the result for one batch in a [FakeSyncAdapter].
typedef FakeBatchHandler = FutureOr<SyncResult> Function(List<SyncTask> batch);

/// Scriptable [SyncAdapter] for tests and demos.
///
/// Succeeds for every task by default. Every batch it receives is recorded
/// in [batches] so tests can assert what was sent and in which order.
///
/// ```dart
/// final adapter = FakeSyncAdapter()
///   ..failNext(1, error: 'HTTP 503');      // first batch fails
/// ```
class FakeSyncAdapter implements SyncAdapter {
  /// Every batch received, in order. Tasks are copies taken at send time.
  final List<List<SyncTask>> batches = [];

  /// Fallback handler used when no scripted response is queued.
  FakeBatchHandler handler;

  /// Optional artificial latency for each batch.
  Duration latency;

  final List<FakeBatchHandler> _script = [];

  /// Creates a [FakeSyncAdapter]. Succeeds for every task unless a
  /// [handler] is given.
  FakeSyncAdapter({FakeBatchHandler? handler, this.latency = Duration.zero})
      : handler = handler ?? _succeedAll;

  static SyncResult _succeedAll(List<SyncTask> batch) =>
      SyncResult.allSuccess(batch.map((t) => t.taskId).toList());

  /// All tasks sent so far, flattened.
  List<SyncTask> get sentTasks => batches.expand((b) => b).toList();

  /// TaskIds sent so far, flattened, in order.
  List<String> get sentTaskIds => sentTasks.map((t) => t.taskId).toList();

  /// Queues a one-off handler for the next batch.
  void enqueueResponse(FakeBatchHandler response) => _script.add(response);

  /// Fails the next [count] batches entirely with [error].
  void failNext(int count,
      {String error = 'Simulated failure', bool permanent = false}) {
    for (var i = 0; i < count; i++) {
      _script.add((batch) => SyncResult.allFailed(
            {for (final t in batch) t.taskId: error},
            permanent: permanent,
          ));
    }
  }

  /// Makes the next [count] batches throw [error].
  void throwNext(int count, Object error) {
    for (var i = 0; i < count; i++) {
      _script.add((_) => throw error);
    }
  }

  @override
  Future<SyncResult> syncBatch(List<SyncTask> tasks) async {
    batches.add(tasks.map((t) => t.copyWith()).toList());
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    final next = _script.isNotEmpty ? _script.removeAt(0) : handler;
    return next(tasks);
  }
}
