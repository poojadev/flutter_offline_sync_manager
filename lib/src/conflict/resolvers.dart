import '../core/sync_task.dart';
import 'conflict_resolution.dart';
import 'resolution_result.dart';
import '../dirty_tracking/dirty_payload_builder.dart';

/// Last write wins resolver.
///
/// Compares timestamps and uses the version with the most recent update time.
/// If timestamps are equal or unavailable, client data is preferred.
class LastWriteWinsResolver implements ConflictResolver {
  const LastWriteWinsResolver();

  @override
  ResolutionResult resolve({
    required SyncTask localTask,
    required Map<String, dynamic> serverData,
  }) {
    // Extract timestamps
    final localUpdatedAt = localTask.updatedAt;
    final serverUpdatedAt = _extractTimestamp(serverData, 'updatedAt') ??
        _extractTimestamp(serverData, 'updated_at') ??
        _extractTimestamp(serverData, 'modifiedAt') ??
        _extractTimestamp(serverData, 'modified_at');

    // If server has timestamp and it's newer, server wins
    if (serverUpdatedAt != null && serverUpdatedAt.isAfter(localUpdatedAt)) {
      return ResolutionResult.retry(serverData, ResolutionSource.server);
    }

    // Otherwise, client wins (local data is newer or timestamps equal)
    return ResolutionResult.retry(localTask.payload, ResolutionSource.client);
  }

  DateTime? _extractTimestamp(Map<String, dynamic> data, String fieldName) {
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

/// Server wins resolver.
///
/// Always discards local changes in favor of server data.
/// The task is marked as synced with server data.
class ServerWinsResolver implements ConflictResolver {
  const ServerWinsResolver();

  @override
  ResolutionResult resolve({
    required SyncTask localTask,
    required Map<String, dynamic> serverData,
  }) {
    // Accept server data, mark as synced (no retry needed)
    return ResolutionResult.accept(serverData);
  }
}

/// Client wins resolver.
///
/// Always preserves local changes and retries with local payload.
/// Server data is ignored.
class ClientWinsResolver implements ConflictResolver {
  const ClientWinsResolver();

  @override
  ResolutionResult resolve({
    required SyncTask localTask,
    required Map<String, dynamic> serverData,
  }) {
    // Retry with local payload
    return ResolutionResult.retry(localTask.payload, ResolutionSource.client);
  }
}

/// Field-level merge resolver.
///
/// Performs a safe, shallow merge of local and server data:
/// - Non-conflicting fields from both sources are included
/// - Conflicting fields use client values (local takes precedence)
/// - Unknown fields from server are preserved
/// - No deep recursive merge (v1 limitation)
///
/// This is a conservative merge that prioritizes local changes
/// while preserving server data where possible.
class FieldLevelMergeResolver implements ConflictResolver {
  const FieldLevelMergeResolver();

  @override
  ResolutionResult resolve({
    required SyncTask localTask,
    required Map<String, dynamic> serverData,
  }) {
    // If dirty state exists, use field-level merge with dirty fields only
    if (localTask.dirtyState != null && localTask.dirtyState!.hasDirtyFields) {
      // Merge only dirty fields from client with clean fields from server
      final merged = DirtyPayloadBuilder.mergePartialIntoFull(
        fullPayload: serverData,
        partialPayload: localTask.payload,
        dirtyState: localTask.dirtyState!,
      );
      return ResolutionResult.retry(merged, ResolutionSource.merged);
    }

    // Fallback to full payload merge (backward compatibility)
    final localPayload = Map<String, dynamic>.from(localTask.payload);
    final serverPayload = Map<String, dynamic>.from(serverData);

    // Start with server data as base
    final merged = Map<String, dynamic>.from(serverPayload);

    // Overlay local changes (client wins for conflicting fields)
    for (final entry in localPayload.entries) {
      final key = entry.key;
      final localValue = entry.value;

      // Skip metadata fields that shouldn't be merged
      if (_isMetadataField(key)) {
        continue;
      }

      // If field exists in both, client value wins
      // If field only exists in local, include it
      merged[key] = localValue;
    }

    // Preserve server metadata fields that don't exist in local
    for (final entry in serverPayload.entries) {
      if (_isMetadataField(entry.key) && !localPayload.containsKey(entry.key)) {
        merged[entry.key] = entry.value;
      }
    }

    return ResolutionResult.retry(merged, ResolutionSource.merged);
  }

  /// Checks if a field is a metadata field that shouldn't be merged.
  bool _isMetadataField(String key) {
    final metadataFields = [
      'id',
      '_id',
      'createdAt',
      'created_at',
      'updatedAt',
      'updated_at',
      'version',
      '_version',
      'etag',
      '_etag',
      'syncStatus',
      '_syncStatus',
    ];
    return metadataFields.contains(key) || key.startsWith('_');
  }
}
