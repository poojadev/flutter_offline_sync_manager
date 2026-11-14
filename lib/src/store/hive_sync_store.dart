import 'package:hive/hive.dart';
import '../../flutter_offline_sync_manager.dart';

/// Hive-based implementation of [SyncStore].
///
/// Uses a single Hive box (named "sync_tasks" by default) with taskId as
/// the key. This ensures no duplicates and allows efficient lookups.
///
/// Pass an [encryptionCipher] (for example `HiveAesCipher(key)`) to encrypt
/// queued payloads at rest. Keep the key in secure storage such as
/// `flutter_secure_storage`; the same key must be used on every launch.
class HiveSyncStore implements SyncStore {
  /// Default box name.
  static const String defaultBoxName = 'sync_tasks';

  /// Name of the Hive box holding the queue.
  final String boxName;

  /// Optional cipher used to encrypt the box.
  final HiveCipher? encryptionCipher;

  Box<SyncTask>? _box;

  /// Creates a [HiveSyncStore].
  ///
  /// Use a different [boxName] per user or account to keep queues separate.
  HiveSyncStore({this.boxName = defaultBoxName, this.encryptionCipher});

  /// Initializes the Hive box for storing sync tasks.
  ///
  /// Must be called before using any other methods.
  /// This method is idempotent and safe to call multiple times.
  Future<void> initialize() async {
    if (_box != null && _box!.isOpen) {
      return;
    }

    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(SyncTaskAdapter());
    }

    _box = await Hive.openBox<SyncTask>(
      boxName,
      encryptionCipher: encryptionCipher,
    );
  }

  /// Ensures the box is initialized before operations.
  Future<void> _ensureInitialized() async {
    if (_box == null || !_box!.isOpen) {
      await initialize();
    }
  }

  @override
  Future<void> saveTask(SyncTask task) async {
    await _ensureInitialized();
    await _box!.put(task.taskId, task);
  }

  @override
  Future<void> updateTask(SyncTask task) async {
    await _ensureInitialized();
    await _box!.put(task.taskId, task);
  }

  @override
  Future<SyncTask?> getTask(String taskId) async {
    await _ensureInitialized();
    return _box!.get(taskId)?.copyWith();
  }

  @override
  Future<List<SyncTask>> getAllTasks() async {
    await _ensureInitialized();
    // Return detached copies so callers never mutate Hive's cached objects.
    return _box!.values.map((t) => t.copyWith()).toList();
  }

  @override
  Future<void> deleteTask(String taskId) async {
    await _ensureInitialized();
    await _box!.delete(taskId);
  }

  @override
  Future<List<SyncTask>> getPendingTasks(int limit) async {
    await _ensureInitialized();

    final tasks = <SyncTask>[];
    for (final task in _box!.values) {
      // Include pending and failed tasks, and tasks stuck in syncing state
      // (crash recovery).
      if (task.status == SyncStatus.pending ||
          task.status == SyncStatus.failed ||
          task.status == SyncStatus.syncing) {
        tasks.add(task.copyWith());
      }
    }

    // Sort BEFORE limiting, so the oldest tasks are really returned first.
    tasks.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return tasks.take(limit).toList();
  }

  /// Closes the underlying box.
  Future<void> close() async {
    await _box?.close();
    _box = null;
  }

  @override
  Future<void> markSyncing(String taskId) async {
    await _ensureInitialized();
    final task = _box!.get(taskId);
    if (task != null) {
      task.updateStatus(SyncStatus.syncing);
      await _box!.put(taskId, task);
    }
  }

  @override
  Future<void> markSynced(String taskId) async {
    await _ensureInitialized();
    final task = _box!.get(taskId);
    if (task != null) {
      task.updateStatus(SyncStatus.synced);
      await _box!.put(taskId, task);
    }
  }

  @override
  Future<void> markFailed(String taskId, String error) async {
    await _ensureInitialized();
    final task = _box!.get(taskId);
    if (task != null) {
      task.incrementRetry(error);
      await _box!.put(taskId, task);
    }
  }
}

/// Hive TypeAdapter for [SyncTask].
///
/// Handles serialization and deserialization of [SyncTask] objects.
class SyncTaskAdapter extends TypeAdapter<SyncTask> {
  @override
  final int typeId = 0;

  @override
  SyncTask read(BinaryReader reader) {
    final map = Map<String, dynamic>.from(reader.readMap());
    
    // Parse optional dirty state
    DirtyState? dirtyState;
    if (map['dirtyState'] != null) {
      dirtyState = DirtyState.fromMap(
        Map<String, dynamic>.from(map['dirtyState'] as Map),
      );
    }
    
    return SyncTask(
      entityType: map['entityType'] as String,
      entityId: map['entityId'] as String,
      operation: SyncOperation.values.firstWhere(
        (op) => op.name == map['operation'] as String,
      ),
      payload: Map<String, dynamic>.from(map['payload'] as Map),
      status: SyncStatus.values.firstWhere(
        (s) => s.name == map['status'] as String,
      ),
      retryCount: map['retryCount'] as int,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
      lastError: map['lastError'] as String?,
      dirtyState: dirtyState,
      // Fields added in 0.2.0 fall back to defaults for older records.
      priority: SyncPriority.values.firstWhere(
        (p) => p.name == map['priority'],
        orElse: () => SyncPriority.normal,
      ),
      dependsOn: (map['dependsOn'] as List?)
              ?.map((e) => EntityRef.fromMap(e as Map))
              .toList() ??
          const [],
      revision: (map['revision'] as int?) ?? 0,
      nextAttemptAt: map['nextAttemptAt'] == null
          ? null
          : DateTime.parse(map['nextAttemptAt'] as String),
    );
  }

  @override
  void write(BinaryWriter writer, SyncTask obj) {
    final map = <String, dynamic>{
      'taskId': obj.taskId,
      'entityType': obj.entityType,
      'entityId': obj.entityId,
      'operation': obj.operation.name,
      'payload': obj.payload,
      'status': obj.status.name,
      'retryCount': obj.retryCount,
      'createdAt': obj.createdAt.toIso8601String(),
      'updatedAt': obj.updatedAt.toIso8601String(),
      'lastError': obj.lastError,
      'priority': obj.priority.name,
      'dependsOn': obj.dependsOn.map((d) => d.toMap()).toList(),
      'revision': obj.revision,
      'nextAttemptAt': obj.nextAttemptAt?.toIso8601String(),
    };
    
    // Include dirty state if present
    if (obj.dirtyState != null) {
      map['dirtyState'] = obj.dirtyState!.toMap();
    }
    
    writer.writeMap(map);
  }
}

