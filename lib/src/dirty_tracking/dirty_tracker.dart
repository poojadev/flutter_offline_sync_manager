import 'package:hive/hive.dart';
import 'dirty_state.dart';

/// Core engine for tracking dirty fields per entity.
///
/// Maintains persistent dirty state that survives app restarts and crashes.
/// Developers call this tracker explicitly to mark fields as dirty when
/// entities are modified.
///
/// CRITICAL:
/// - Dirty fields are NEVER cleared until server confirms sync
/// - Dirty state is persisted and crash-safe
/// - Works independently of sync execution
class DirtyTracker {
  static const String _boxName = 'dirty_states';
  Box<Map>? _box;

  /// Initializes the dirty tracker with Hive storage.
  ///
  /// Must be called before using any other methods.
  /// This method is idempotent and safe to call multiple times.
  Future<void> initialize() async {
    if (_box != null && _box!.isOpen) {
      return;
    }

    _box = await Hive.openBox<Map>(_boxName);
  }

  /// Ensures the box is initialized before operations.
  Future<void> _ensureInitialized() async {
    if (_box == null || !_box!.isOpen) {
      await initialize();
    }
  }

  /// Marks a field as dirty for a specific entity.
  ///
  /// If the field is already dirty, updates its timestamp.
  /// This method is idempotent and safe to call multiple times.
  Future<void> markDirty({
    required String entityType,
    required String entityId,
    required String fieldPath,
  }) async {
    await _ensureInitialized();

    final key = _generateKey(entityType, entityId);
    final currentState = await getDirtyState(entityType, entityId);
    final updatedState = currentState.markFieldDirty(fieldPath);

    await _box!.put(key, updatedState.toMap());
  }

  /// Marks multiple fields as dirty for a specific entity.
  ///
  /// All fields are marked with the same timestamp.
  Future<void> markFieldsDirty({
    required String entityType,
    required String entityId,
    required List<String> fieldPaths,
  }) async {
    await _ensureInitialized();

    final key = _generateKey(entityType, entityId);
    final currentState = await getDirtyState(entityType, entityId);
    final updatedState = currentState.markFieldsDirty(fieldPaths);

    await _box!.put(key, updatedState.toMap());
  }

  /// Gets the dirty state for a specific entity.
  ///
  /// Returns an empty [DirtyState] if no dirty state exists.
  Future<DirtyState> getDirtyState(
    String entityType,
    String entityId,
  ) async {
    await _ensureInitialized();

    final key = _generateKey(entityType, entityId);
    final data = _box!.get(key);

    if (data == null) {
      return DirtyState.empty(
        entityType: entityType,
        entityId: entityId,
      );
    }

    return DirtyState.fromMap(Map<String, dynamic>.from(data));
  }

  /// Clears dirty fields that were successfully synced.
  ///
  /// [entityType] - Type of entity
  /// [entityId] - ID of entity
  /// [syncedFieldPaths] - List of field paths confirmed by server
  ///
  /// CRITICAL: Only clears fields that were explicitly confirmed by server.
  /// Failed or conflicted fields remain dirty.
  Future<void> clearSyncedFields({
    required String entityType,
    required String entityId,
    required List<String> syncedFieldPaths,
  }) async {
    await _ensureInitialized();

    final key = _generateKey(entityType, entityId);
    final currentState = await getDirtyState(entityType, entityId);
    final updatedState = currentState.clearSyncedFields(syncedFieldPaths);

    await _box!.put(key, updatedState.toMap());
  }

  /// Clears all dirty fields for an entity.
  ///
  /// Should only be called after all fields are confirmed synced by server.
  Future<void> clearAll({
    required String entityType,
    required String entityId,
  }) async {
    await _ensureInitialized();

    final key = _generateKey(entityType, entityId);
    final currentState = await getDirtyState(entityType, entityId);
    final updatedState = currentState.clearAll();

    await _box!.put(key, updatedState.toMap());
  }

  /// Removes dirty state for an entity entirely.
  ///
  /// Use this when an entity is deleted or no longer needs tracking.
  Future<void> remove({
    required String entityType,
    required String entityId,
  }) async {
    await _ensureInitialized();

    final key = _generateKey(entityType, entityId);
    await _box!.delete(key);
  }

  /// Generates a storage key for an entity's dirty state.
  String _generateKey(String entityType, String entityId) {
    return '${entityType}_$entityId';
  }
}

