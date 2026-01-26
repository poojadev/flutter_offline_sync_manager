import 'package:hive/hive.dart';
import 'sync_operation.dart';
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

  /// Number of times this task has been retried after failure.
  late int retryCount;

  /// Timestamp when the task was created.
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

  /// Whether this task represents a partial update (only dirty fields).
  ///
  /// This is derived from [dirtyState] - if dirtyState exists and has
  /// dirty fields, this is true. Otherwise false.
  bool get isPartialUpdate => dirtyState != null && dirtyState!.hasDirtyFields;

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
    this.taskId = _generateTaskId(entityType, entityId, operation);
  }

  /// Generates a deterministic task ID from entity type, ID, and operation.
  ///
  /// This ensures that multiple updates to the same entity will result
  /// in the same taskId, allowing safe overwrites and preventing duplicates.
  static String _generateTaskId(
    String entityType,
    String entityId,
    SyncOperation operation,
  ) {
    return '${entityType}_${entityId}_${operation.name}';
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
}

