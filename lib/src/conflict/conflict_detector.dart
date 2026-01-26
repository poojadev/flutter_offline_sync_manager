import '../core/sync_task.dart';

/// Result of conflict detection.
class ConflictDetectedResult {
  /// Whether a conflict was detected.
  final bool hasConflict;

  /// Metadata about the conflict (e.g., conflicting fields, version info).
  final Map<String, dynamic> metadata;

  /// Server data that conflicts with local data.
  final Map<String, dynamic>? serverData;

  /// Creates a [ConflictDetectedResult].
  const ConflictDetectedResult({
    required this.hasConflict,
    this.metadata = const {},
    this.serverData,
  });

  /// Creates a result indicating no conflict.
  factory ConflictDetectedResult.noConflict() {
    return const ConflictDetectedResult(hasConflict: false);
  }

  /// Creates a result indicating a conflict was detected.
  factory ConflictDetectedResult.conflict({
    required Map<String, dynamic> serverData,
    Map<String, dynamic>? metadata,
  }) {
    return ConflictDetectedResult(
      hasConflict: true,
      serverData: serverData,
      metadata: metadata ?? {},
    );
  }
}

/// Detects conflicts between local and server data.
///
/// This class is responsible for determining if a conflict exists,
/// but does NOT resolve conflicts. Resolution is handled by [ConflictResolver].
///
/// Detection can be based on:
/// - Version mismatch (e.g., ETag, version field)
/// - Timestamp comparison (updatedAt)
/// - Server error codes indicating conflict
/// - Explicit conflict flags in server response
abstract class ConflictDetector {
  /// Detects if a conflict exists between local task and server response.
  ///
  /// [localTask] is the task that was sent to the server.
  /// [serverResponse] is the response from the server (may be error or data).
  /// [errorMessage] is the error message if the sync failed.
  ///
  /// Returns [ConflictDetectedResult] indicating if a conflict exists
  /// and providing metadata about the conflict.
  ConflictDetectedResult detect({
    required SyncTask localTask,
    Map<String, dynamic>? serverResponse,
    String? errorMessage,
  });
}

/// Default implementation of [ConflictDetector].
///
/// Detects conflicts based on:
/// - Explicit conflict flags in server response
/// - Version mismatch (checks for 'version' or 'etag' fields)
/// - Timestamp comparison (if server returns updatedAt)
/// - Common conflict error messages (409, 'conflict', 'version mismatch')
class DefaultConflictDetector implements ConflictDetector {
  /// Creates a [DefaultConflictDetector].
  const DefaultConflictDetector();

  @override
  ConflictDetectedResult detect({
    required SyncTask localTask,
    Map<String, dynamic>? serverResponse,
    String? errorMessage,
  }) {
    // Check for explicit conflict flag in server response
    if (serverResponse != null) {
      if (serverResponse['_conflict'] == true ||
          serverResponse['conflict'] == true) {
        return ConflictDetectedResult.conflict(
          serverData: serverResponse,
          metadata: {'reason': 'explicit_conflict_flag'},
        );
      }

      // Check for version mismatch
      final localVersion = _extractVersion(localTask.payload);
      final serverVersion = _extractVersion(serverResponse);
      if (localVersion != null &&
          serverVersion != null &&
          localVersion != serverVersion) {
        return ConflictDetectedResult.conflict(
          serverData: serverResponse,
          metadata: {
            'reason': 'version_mismatch',
            'localVersion': localVersion,
            'serverVersion': serverVersion,
          },
        );
      }

      // Check for timestamp comparison (if server has updatedAt)
      final serverUpdatedAt = _extractTimestamp(serverResponse, 'updatedAt');
      if (serverUpdatedAt != null) {
        // If server data is newer, potential conflict
        // (This is a simple heuristic - actual conflict depends on business logic)
        final localUpdatedAt = localTask.updatedAt;
        if (serverUpdatedAt.isAfter(localUpdatedAt)) {
          // Server has newer data, but this alone doesn't mean conflict
          // We need an error or explicit flag to confirm conflict
        }
      }
    }

    // Check error message for conflict indicators
    if (errorMessage != null) {
      final lowerError = errorMessage.toLowerCase();
      if (lowerError.contains('conflict') ||
          lowerError.contains('version mismatch') ||
          lowerError.contains('409') ||
          lowerError.contains('precondition failed') ||
          lowerError.contains('optimistic lock')) {
        return ConflictDetectedResult.conflict(
          serverData: serverResponse ?? {},
          metadata: {
            'reason': 'error_message',
            'error': errorMessage,
          },
        );
      }
    }

    // No conflict detected
    return ConflictDetectedResult.noConflict();
  }

  /// Extracts version from a data map.
  ///
  /// Checks common version field names: 'version', 'etag', '_version', '_etag'.
  int? _extractVersion(Map<String, dynamic>? data) {
    if (data == null) return null;

    final versionFields = ['version', 'etag', '_version', '_etag'];
    for (final field in versionFields) {
      final value = data[field];
      if (value is int) return value;
      if (value is String) {
        // Try to parse as int
        final parsed = int.tryParse(value);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  /// Extracts timestamp from a data map.
  DateTime? _extractTimestamp(
    Map<String, dynamic>? data,
    String fieldName,
  ) {
    if (data == null) return null;

    final value = data[fieldName];
    if (value is DateTime) return value;
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (e) {
        return null;
      }
    }
    return null;
  }
}

