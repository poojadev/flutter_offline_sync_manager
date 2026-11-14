import 'dirty_state.dart';

/// Utility for building partial payloads containing only dirty fields.
///
/// Takes a full entity payload and a dirty state, and returns a partial
/// payload containing only the fields that were marked as dirty.
///
/// CRITICAL:
/// - Preserves nested structure
/// - Never includes clean fields
/// - Never drops unknown fields
/// - Falls back to full payload if no dirty fields exist
class DirtyPayloadBuilder {
  /// Builds a partial payload containing only dirty fields.
  ///
  /// [fullPayload] - The complete entity payload
  /// [dirtyState] - The dirty state containing which fields are dirty
  ///
  /// Returns a partial payload with only dirty fields, or the full payload
  /// if no dirty fields exist or dirty state is null.
  static Map<String, dynamic> buildPartialPayload({
    required Map<String, dynamic> fullPayload,
    DirtyState? dirtyState,
  }) {
    // If no dirty state or no dirty fields, return full payload
    if (dirtyState == null || !dirtyState.hasDirtyFields) {
      return Map<String, dynamic>.from(fullPayload);
    }

    final dirtyFieldPaths = dirtyState.dirtyFieldPaths;
    final partialPayload = <String, dynamic>{};

    // Extract only dirty fields from full payload
    for (final fieldPath in dirtyFieldPaths) {
      final value = _extractFieldValue(fullPayload, fieldPath);
      if (value != null) {
        _setFieldValue(partialPayload, fieldPath, value);
      }
    }

    // If partial payload is empty, fallback to full payload
    if (partialPayload.isEmpty) {
      return Map<String, dynamic>.from(fullPayload);
    }

    return partialPayload;
  }

  /// Extracts a field value from a nested map using dot-notation path.
  ///
  /// Examples:
  /// - "title" -> payload["title"]
  /// - "symptoms.fatigue.level" -> payload["symptoms"]["fatigue"]["level"]
  static dynamic _extractFieldValue(
    Map<String, dynamic> payload,
    String fieldPath,
  ) {
    final parts = fieldPath.split('.');
    dynamic current = payload;

    for (final part in parts) {
      if (current is Map<String, dynamic>) {
        current = current[part];
        if (current == null) {
          return null;
        }
      } else {
        return null;
      }
    }

    return current;
  }

  /// Sets a field value in a nested map using dot-notation path.
  ///
  /// Creates nested maps as needed to preserve structure.
  static void _setFieldValue(
    Map<String, dynamic> payload,
    String fieldPath,
    dynamic value,
  ) {
    final parts = fieldPath.split('.');
    Map<String, dynamic> current = payload;

    // Navigate/create nested structure
    for (int i = 0; i < parts.length - 1; i++) {
      final part = parts[i];
      if (!current.containsKey(part) || current[part] is! Map) {
        current[part] = <String, dynamic>{};
      }
      current = current[part] as Map<String, dynamic>;
    }

    // Set the final value
    current[parts.last] = value;
  }

  /// Merges a partial payload into a full payload at the field level.
  ///
  /// This is used during conflict resolution to merge dirty client fields
  /// with clean server fields.
  ///
  /// [fullPayload] - The complete payload (typically from server)
  /// [partialPayload] - The partial payload containing dirty fields (from client)
  /// [dirtyState] - The dirty state indicating which fields are dirty
  ///
  /// Returns a merged payload where:
  /// - Dirty fields from partial payload overwrite full payload
  /// - Clean fields from full payload are preserved
  static Map<String, dynamic> mergePartialIntoFull({
    required Map<String, dynamic> fullPayload,
    required Map<String, dynamic> partialPayload,
    required DirtyState dirtyState,
  }) {
    final merged = Map<String, dynamic>.from(fullPayload);

    // Overlay dirty fields from partial payload
    for (final fieldPath in dirtyState.dirtyFieldPaths) {
      final dirtyValue = _extractFieldValue(partialPayload, fieldPath);
      if (dirtyValue != null) {
        _setFieldValue(merged, fieldPath, dirtyValue);
      }
    }

    return merged;
  }
}
