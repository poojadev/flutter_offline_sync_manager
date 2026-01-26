import 'dirty_field.dart';

/// Container that holds dirty fields for a specific entity.
///
/// Tracks which fields of an entity have been modified and need to be synced.
/// This state is persisted and survives app restarts.
class DirtyState {
  /// The type of entity (e.g., 'journal_entry', 'user', 'post').
  final String entityType;

  /// The unique identifier of the entity.
  final String entityId;

  /// Map of field paths to their dirty field information.
  ///
  /// Key is the field path (e.g., "title", "symptoms.fatigue.level").
  /// Value is the [DirtyField] containing the path and timestamp.
  final Map<String, DirtyField> dirtyFields;

  /// Timestamp when this dirty state was last updated.
  final DateTime updatedAt;

  /// Creates a [DirtyState] with the given parameters.
  DirtyState({
    required this.entityType,
    required this.entityId,
    Map<String, DirtyField>? dirtyFields,
    DateTime? updatedAt,
  })  : dirtyFields = dirtyFields ?? <String, DirtyField>{},
        updatedAt = updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  /// Creates an empty [DirtyState] for a new entity.
  factory DirtyState.empty({
    required String entityType,
    required String entityId,
  }) {
    return DirtyState(
      entityType: entityType,
      entityId: entityId,
      dirtyFields: {},
      updatedAt: DateTime.now(),
    );
  }

  /// Creates a [DirtyState] from a map (for serialization).
  factory DirtyState.fromMap(Map<String, dynamic> map) {
    final dirtyFieldsMap = map['dirtyFields'] as Map<String, dynamic>? ?? {};
    final dirtyFields = <String, DirtyField>{};
    for (final entry in dirtyFieldsMap.entries) {
      dirtyFields[entry.key] = DirtyField.fromMap(
        Map<String, dynamic>.from(entry.value),
      );
    }

    return DirtyState(
      entityType: map['entityType'] as String,
      entityId: map['entityId'] as String,
      dirtyFields: dirtyFields,
      updatedAt: DateTime.parse(map['updatedAt'] as String),
    );
  }

  /// Converts this [DirtyState] to a map (for serialization).
  Map<String, dynamic> toMap() {
    final dirtyFieldsMap = <String, dynamic>{};
    for (final entry in dirtyFields.entries) {
      dirtyFieldsMap[entry.key] = entry.value.toMap();
    }

    return {
      'entityType': entityType,
      'entityId': entityId,
      'dirtyFields': dirtyFieldsMap,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// Marks a field as dirty.
  ///
  /// If the field is already dirty, updates its timestamp.
  /// Returns a new [DirtyState] with the updated dirty fields.
  DirtyState markFieldDirty(String fieldPath) {
    final updatedFields = Map<String, DirtyField>.from(dirtyFields);
    updatedFields[fieldPath] = DirtyField.now(fieldPath);

    return DirtyState(
      entityType: entityType,
      entityId: entityId,
      dirtyFields: updatedFields,
      updatedAt: DateTime.now(),
    );
  }

  /// Marks multiple fields as dirty.
  ///
  /// Returns a new [DirtyState] with all specified fields marked as dirty.
  DirtyState markFieldsDirty(List<String> fieldPaths) {
    final updatedFields = Map<String, DirtyField>.from(dirtyFields);
    final now = DateTime.now();

    for (final fieldPath in fieldPaths) {
      updatedFields[fieldPath] = DirtyField(
        fieldPath: fieldPath,
        updatedAt: now,
      );
    }

    return DirtyState(
      entityType: entityType,
      entityId: entityId,
      dirtyFields: updatedFields,
      updatedAt: now,
    );
  }

  /// Clears dirty fields that were successfully synced.
  ///
  /// [syncedFieldPaths] - List of field paths that were confirmed by server.
  /// Returns a new [DirtyState] with those fields removed.
  DirtyState clearSyncedFields(List<String> syncedFieldPaths) {
    final updatedFields = Map<String, DirtyField>.from(dirtyFields);
    for (final fieldPath in syncedFieldPaths) {
      updatedFields.remove(fieldPath);
    }

    return DirtyState(
      entityType: entityType,
      entityId: entityId,
      dirtyFields: updatedFields,
      updatedAt: DateTime.now(),
    );
  }

  /// Clears all dirty fields (use with caution).
  ///
  /// Should only be called after all fields are confirmed synced by server.
  DirtyState clearAll() {
    return DirtyState(
      entityType: entityType,
      entityId: entityId,
      dirtyFields: {},
      updatedAt: DateTime.now(),
    );
  }

  /// Checks if a specific field is dirty.
  bool isFieldDirty(String fieldPath) {
    return dirtyFields.containsKey(fieldPath);
  }

  /// Checks if there are any dirty fields.
  bool get hasDirtyFields => dirtyFields.isNotEmpty;

  /// Gets the list of all dirty field paths.
  List<String> get dirtyFieldPaths => dirtyFields.keys.toList();
}

