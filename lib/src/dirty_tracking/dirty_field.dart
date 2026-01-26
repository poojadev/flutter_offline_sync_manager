/// Represents a single dirty field that has been modified.
///
/// A dirty field tracks which specific field path was changed and when.
/// Supports nested paths using dot-notation (e.g., "title", "symptoms.fatigue.level").
class DirtyField {
  /// The path to the field that was modified.
  ///
  /// Examples:
  /// - "title" - top-level field
  /// - "symptoms.fatigue.level" - nested field
  /// - "metadata.tags[0]" - array element (if supported by backend)
  final String fieldPath;

  /// Timestamp when this field was last marked as dirty.
  final DateTime updatedAt;

  /// Creates a [DirtyField] with the given path and timestamp.
  const DirtyField({
    required this.fieldPath,
    required this.updatedAt,
  });

  /// Creates a [DirtyField] with the current timestamp.
  factory DirtyField.now(String fieldPath) {
    return DirtyField(
      fieldPath: fieldPath,
      updatedAt: DateTime.now(),
    );
  }

  /// Creates a [DirtyField] from a map (for serialization).
  factory DirtyField.fromMap(Map<String, dynamic> map) {
    return DirtyField(
      fieldPath: map['fieldPath'] as String,
      updatedAt: DateTime.parse(map['updatedAt'] as String),
    );
  }

  /// Converts this [DirtyField] to a map (for serialization).
  Map<String, dynamic> toMap() {
    return {
      'fieldPath': fieldPath,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DirtyField &&
        other.fieldPath == fieldPath &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => fieldPath.hashCode ^ updatedAt.hashCode;
}

