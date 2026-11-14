import 'package:hive/hive.dart';
import 'entity_ref.dart';
import 'sync_operation.dart';
import 'sync_priority.dart';
import 'sync_status.dart';
import '../dirty_tracking/dirty_state.dart';

/// Represents a single sync task that needs to be synchronized with the server.
///
/// The [taskId] is deterministic and derived from [entityType], [entityId],
/// and [operation]. This ensures that multiple updates to the same entity
/// will overwrite the same task, preventing duplicates.
class SyncTask extends HiveObject {
  /// Deterministic task identifier derived from entityType + entityId + operation.
  /// This ensures that updates to the same entity overwrite the same task.
  late String taskId;

  /// The type of entity being synced (e.g., 'user', 'post', 'comment').
  late String entityType;

  /// The unique identifier of the entity being synced.
  late String entityId;

  /// The operation to perform on the server.
  late SyncOperation operation;

  /// The data payload to send to the server.
  late Map<String, dynamic> payload;

  /// Current status of the sync task.
  late SyncStatus status;

  /// Number of times this task has failed (including conflicts).
  late int retryCount;

  /// Timestamp when the task was created.
  ///
  /// This is the task's position in the queue. It is preserved when the task
  /// is overwritten or coalesced so that ordering stays stable.
  late DateTime createdAt;

  /// Timestamp when the task was last updated.
  late DateTime updatedAt;

  /// Error message from the last failed sync attempt, if any.
  String? lastError;

  /// Optional dirty state tracking which fields are dirty.
  ///
  /// If provided, indicates that this is a partial update containing
  /// only the fields marked as dirty. If null, the full payload is used.
  DirtyState? dirtyState;

  /// Priority of this task. Higher priorities are sent first.
  late SyncPriority priority;

  /// Entities that must be fully synced before this task is sent.
  late List<EntityRef> dependsOn;

  /// Monotonic revision, bumped every time the task's content changes.
  ///
  /// Used to detect edits that happen while the task is in flight, so a
  /// newer local change is never marked as synced by an older server ack.
  late int revision;

  /// Earliest time this task may be retried after a failure.
  ///
  /// `null` means the task is eligible immediately.
  DateTime? nextAttemptAt;

  /// Whether this task represents a partial update (only dirty fields).
  ///
  /// This is derived from [dirtyState] - if dirtyState exists and has
  /// dirty fields, this is true. Otherwise false.
  bool get isPartialUpdate => dirtyState != null && dirtyState!.hasDirtyFields;

  /// Stable key of the entity this task belongs to.
  String get entityKey => EntityRef.entityKey(entityType, entityId);

  /// Reference to the entity this task belongs to.
  EntityRef get entityRef => EntityRef(entityType, entityId);

  /// Whether this task still needs to reach the server (not synced).
  bool get isOutstanding => status != SyncStatus.synced;

  /// Creates a [SyncTask] with the given parameters.
  ///
  /// The [taskId] is automatically generated from [entityType], [entityId],
  /// and [operation] to ensure determinism and prevent duplicates.
  SyncTask({
    required String entityType,
    required String entityId,
    required SyncOperation operation,
    required Map<String, dynamic> payload,
    SyncStatus status = SyncStatus.pending,
    int retryCount = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? lastError,
    DirtyState? dirtyState,
    SyncPriority priority = SyncPriority.normal,
    List<EntityRef> dependsOn = const [],
    int revision = 0,
    DateTime? nextAttemptAt,
  }) {
    this.entityType = entityType;
    this.entityId = entityId;
    this.operation = operation;
    this.payload = payload;
    this.status = status;
    this.retryCount = retryCount;
    this.createdAt = createdAt ?? DateTime.now();
    this.updatedAt = updatedAt ?? DateTime.now();
    this.lastError = lastError;
    this.dirtyState = dirtyState;
    this.priority = priority;
    this.dependsOn = List.unmodifiable(dependsOn);
    this.revision = revision;
    this.nextAttemptAt = nextAttemptAt;
    this.taskId = generateTaskId(entityType, entityId, operation);
  }

  /// Generates a deterministic task ID from entity type, ID, and operation.
  ///
  /// This ensures that multiple updates to the same entity will result
  /// in the same taskId, allowing safe overwrites and preventing duplicates.
  static String generateTaskId(
    String entityType,
    String entityId,
    SyncOperation operation,
  ) {
    return '${entityType}_${entityId}_${operation.name}';
  }

  /// Returns a copy of this task with the given fields replaced.
  ///
  /// Copies are detached from any Hive box, so they can be modified and
  /// saved without mutating cached instances.
  SyncTask copyWith({
    SyncOperation? operation,
    Map<String, dynamic>? payload,
    SyncStatus? status,
    int? retryCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? lastError,
    bool clearLastError = false,
    DirtyState? dirtyState,
    bool clearDirtyState = false,
    SyncPriority? priority,
    List<EntityRef>? dependsOn,
    int? revision,
    DateTime? nextAttemptAt,
    bool clearNextAttemptAt = false,
  }) {
    return SyncTask(
      entityType: entityType,
      entityId: entityId,
      operation: operation ?? this.operation,
      payload: payload ?? Map<String, dynamic>.from(this.payload),
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      dirtyState: clearDirtyState ? null : (dirtyState ?? this.dirtyState),
      priority: priority ?? this.priority,
      dependsOn: dependsOn ?? this.dependsOn,
      revision: revision ?? this.revision,
      nextAttemptAt:
          clearNextAttemptAt ? null : (nextAttemptAt ?? this.nextAttemptAt),
    );
  }

  /// Updates the task's status and timestamp.
  void updateStatus(SyncStatus newStatus, {String? error}) {
    status = newStatus;
    updatedAt = DateTime.now();
    if (error != null) {
      lastError = error;
    }
  }

  /// Increments the retry count and updates the status to failed.
  void incrementRetry(String error) {
    retryCount++;
    updateStatus(SyncStatus.failed, error: error);
  }

  @override
  String toString() =>
      'SyncTask($taskId, status: ${status.name}, priority: ${priority.name}, '
      'retries: $retryCount, rev: $revision)';
}
