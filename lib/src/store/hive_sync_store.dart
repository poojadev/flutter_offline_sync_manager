import 'package:hive/hive.dart';
import '../../flutter_offline_sync_manager.dart';

/// Hive-based implementation of [SyncStore].
///
/// Uses a single Hive box named "sync_tasks" with taskId as the key.
/// This ensures no duplicates and allows efficient lookups.
class HiveSyncStore implements SyncStore {
  static const String _boxName = 'sync_tasks';
  Box<SyncTask>? _box;

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

    _box = await Hive.openBox<SyncTask>(_boxName);
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
  Future<List<SyncTask>> getPendingTasks(int limit) async {
    await _ensureInitialized();

    final tasks = <SyncTask>[];
    for (final key in _box!.keys) {
      final task = _box!.get(key);
      if (task == null) continue;

      // Include pending and failed tasks
      // Also include tasks stuck in syncing state (from crash recovery)
      if (task.status == SyncStatus.pending ||
          task.status == SyncStatus.failed ||
          task.status == SyncStatus.syncing) {
        // Reset syncing tasks to pending for retry (crash recovery)
        if (task.status == SyncStatus.syncing) {
          task.updateStatus(SyncStatus.pending);
          await _box!.put(task.taskId, task);
        }
        tasks.add(task);
      }

      if (tasks.length >= limit) {
        break;
      }
    }

    // Sort by createdAt to process oldest tasks first
    tasks.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return tasks;
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
    };
    
    // Include dirty state if present
    if (obj.dirtyState != null) {
      map['dirtyState'] = obj.dirtyState!.toMap();
    }
    
    writer.writeMap(map);
  }
}

