import 'entity_ref.dart';
import 'sync_operation.dart';
import 'sync_priority.dart';
import 'sync_status.dart';
import 'sync_task.dart';

/// How an incoming change was folded into the queue.
enum CompactionKind {
  /// Added as a new task (nothing to merge with).
  appended,

  /// Overwrote an existing task with the same taskId.
  replaced,

  /// Merged into the previous queued task for the same entity.
  merged,

  /// Cancelled out the previous task (create + delete of an entity the
  /// server never saw), so nothing is sent.
  annihilated,
}

/// The store changes needed to apply an incoming change.
class CompactionPlan {
  /// What happened.
  final CompactionKind kind;

  /// The task to save, or null when nothing needs sending.
  final SyncTask? save;

  /// TaskIds to delete from the store.
  final List<String> remove;

  /// Creates a [CompactionPlan].
  const CompactionPlan({
    required this.kind,
    required this.save,
    this.remove = const [],
  });
}

/// Folds a new change for an entity into the tasks already queued for it.
///
/// Pure logic, no I/O: the manager loads the entity's outstanding tasks,
/// asks for a plan, and applies it.
class QueueCompactor {
  const QueueCompactor._();

  /// Plans how to apply [incoming] given the entity's [existing] tasks.
  ///
  /// [existing] must contain only the outstanding (not synced) tasks of the
  /// same entity. When [coalesce] is false only same-taskId overwrites are
  /// applied (the pre-0.2 behaviour).
  static CompactionPlan plan({
    required List<SyncTask> existing,
    required SyncTask incoming,
    bool coalesce = true,
  }) {
    final ordered = [...existing]..sort(compareQueueOrder);

    if (coalesce && ordered.isNotEmpty) {
      final prev = ordered.last;
      final merged = _coalesce(prev, incoming);
      if (merged != null) return merged;
    }

    // No merge: overwrite a task with the same id, or append.
    final sameId = existing.where((t) => t.taskId == incoming.taskId);
    if (sameId.isNotEmpty) {
      final current = sameId.first;
      return CompactionPlan(
        kind: CompactionKind.replaced,
        save: incoming.copyWith(
          // Keep the queue position and bump the revision so an in-flight
          // copy of the old content is never acknowledged as this one.
          createdAt: current.createdAt,
          revision: current.revision + 1,
          priority: _maxPriority(current.priority, incoming.priority),
          dependsOn: _union(current.dependsOn, incoming.dependsOn),
          status: SyncStatus.pending,
          retryCount: 0,
          clearNextAttemptAt: true,
          clearLastError: true,
        ),
      );
    }
    return CompactionPlan(kind: CompactionKind.appended, save: incoming);
  }

  static CompactionPlan? _coalesce(SyncTask prev, SyncTask incoming) {
    // Never merge into a task that is in flight or parked.
    if (prev.status != SyncStatus.pending && prev.status != SyncStatus.failed) {
      return null;
    }

    final p = prev.operation;
    final n = incoming.operation;
    SyncOperation? op;

    switch (p) {
      case SyncOperation.create:
        if (n == SyncOperation.delete) {
          final neverAttempted = prev.retryCount == 0 && prev.lastError == null;
          if (neverAttempted) {
            return CompactionPlan(
              kind: CompactionKind.annihilated,
              save: null,
              remove: [prev.taskId],
            );
          }
          // The create may have reached the server before failing,
          // so the delete must still be sent.
          op = SyncOperation.delete;
        } else {
          op = SyncOperation.create;
        }
        break;
      case SyncOperation.update:
      case SyncOperation.upsert:
        if (n == SyncOperation.delete) {
          op = SyncOperation.delete;
        } else if (n == SyncOperation.create) {
          return null; // Unusual sequence; keep both, in order.
        } else {
          op = (p == SyncOperation.upsert || n == SyncOperation.upsert)
              ? SyncOperation.upsert
              : SyncOperation.update;
        }
        break;
      case SyncOperation.delete:
        return null; // Changes after a delete are kept as-is, in order.
    }

    final payload = op == SyncOperation.delete
        ? Map<String, dynamic>.from(incoming.payload)
        : <String, dynamic>{...prev.payload, ...incoming.payload};

    final merged = SyncTask(
      entityType: prev.entityType,
      entityId: prev.entityId,
      operation: op,
      payload: payload,
      status: prev.status,
      retryCount: prev.retryCount,
      createdAt: prev.createdAt,
      updatedAt: incoming.updatedAt,
      lastError: prev.lastError,
      dirtyState: op == SyncOperation.delete
          ? null
          : (incoming.dirtyState ?? prev.dirtyState),
      priority: _maxPriority(prev.priority, incoming.priority),
      dependsOn: _union(prev.dependsOn, incoming.dependsOn),
      revision: prev.revision + 1,
      nextAttemptAt: prev.nextAttemptAt,
    );

    return CompactionPlan(
      kind: CompactionKind.merged,
      save: merged,
      remove: merged.taskId == prev.taskId ? const [] : [prev.taskId],
    );
  }

  /// Queue order: oldest first, ties broken by taskId for determinism.
  static int compareQueueOrder(SyncTask a, SyncTask b) {
    final c = a.createdAt.compareTo(b.createdAt);
    return c != 0 ? c : a.taskId.compareTo(b.taskId);
  }

  static SyncPriority _maxPriority(SyncPriority a, SyncPriority b) =>
      a.index >= b.index ? a : b;

  static List<EntityRef> _union(List<EntityRef> a, List<EntityRef> b) =>
      {...a, ...b}.toList();
}
