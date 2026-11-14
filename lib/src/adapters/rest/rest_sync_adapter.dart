import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/sync_task.dart';
import '../../core/sync_result.dart';
import 'rest_sync_config.dart';
import '../../adapter/sync_adapter.dart';

/// REST API sync adapter implementation.
///
/// Sends sync tasks to a REST endpoint and handles responses.
///
/// Server Contract:
/// - Endpoint: POST {endpoint}
/// - Request body: JSON array of tasks
/// - Each task object contains:
///   - taskId: string
///   - entityType: string
///   - entityId: string
///   - operation: 'create' | 'update' | 'delete' | 'upsert'
///   - payload: object (full or partial)
///   - updatedAt: ISO 8601 string
/// - Response: JSON object with:
///   - successTaskIds: array of strings
///   - failedTaskErrors: object mapping taskId to error message
///   - conflicts: optional object mapping taskId to server data
///
/// Example usage:
/// ```dart
/// final adapter = RestSyncAdapter(
///   config: RestSyncConfig(
///     endpoint: 'https://api.example.com/sync',
///     headersProvider: () => {'Authorization': 'Bearer $token'},
///   ),
/// );
/// ```
class RestSyncAdapter implements SyncAdapter {
  final RestSyncConfig _config;

  /// Creates a [RestSyncAdapter] with the given configuration.
  RestSyncAdapter({required RestSyncConfig config}) : _config = config;

  @override
  Future<SyncResult> syncBatch(List<SyncTask> tasks) async {
    if (tasks.isEmpty) {
      return const SyncResult(
        successTaskIds: {},
        failedTaskErrors: {},
      );
    }

    try {
      // Prepare request body
      final requestBody = _buildRequestBody(tasks);

      // Call beforeSend hook
      _config.beforeSend?.call(requestBody);

      // Prepare headers
      final headers = <String, String>{
        'Content-Type': 'application/json',
        ...?_config.headersProvider?.call(),
      };

      // Make HTTP request
      final response = await http
          .post(
            Uri.parse(_config.endpoint),
            headers: headers,
            body: jsonEncode(requestBody),
          )
          .timeout(_config.timeout);

      // Parse response
      final responseData = jsonDecode(response.body) as Map<String, dynamic>;

      // Call afterResponse hook
      _config.afterResponse?.call(responseData);

      // Handle response based on status code
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return _parseSuccessResponse(responseData, tasks);
      } else if (_config.isConflictStatusCode(response.statusCode)) {
        return _parseConflictResponse(responseData, tasks, response.statusCode);
      } else if (_config.isRetryableStatusCode(response.statusCode)) {
        // Retryable error - return all tasks as failed
        return _createRetryableErrorResult(tasks, response.statusCode);
      } else {
        // Non-retryable error - return all tasks as failed
        return _createNonRetryableErrorResult(
          tasks,
          response.statusCode,
          responseData,
        );
      }
    } on http.ClientException catch (e) {
      // Network error - retryable
      return _createNetworkErrorResult(tasks, e);
    } on FormatException catch (e) {
      // Invalid JSON response - non-retryable
      return _createValidationErrorResult(tasks, 'Invalid response format: $e');
    } catch (e) {
      // Unknown error - non-retryable
      return _createUnknownErrorResult(tasks, e);
    }
  }

  /// Builds the request body from tasks.
  Map<String, dynamic> _buildRequestBody(List<SyncTask> tasks) {
    return {
      'tasks': tasks.map((task) {
        return {
          'taskId': task.taskId,
          'entityType': task.entityType,
          'entityId': task.entityId,
          'operation': task.operation.name,
          'payload': task.payload,
          'updatedAt': task.updatedAt.toIso8601String(),
          if (task.isPartialUpdate) 'isPartialUpdate': true,
        };
      }).toList(),
    };
  }

  /// Parses a successful response.
  SyncResult _parseSuccessResponse(
    Map<String, dynamic> responseData,
    List<SyncTask> tasks,
  ) {
    final successTaskIds = <String>{};
    final failedTaskErrors = <String, String>{};
    final serverData = <String, Map<String, dynamic>>{};

    // Extract success task IDs
    if (responseData['successTaskIds'] is List) {
      final ids = responseData['successTaskIds'] as List;
      successTaskIds.addAll(ids.map((id) => id.toString()));
    }

    // Extract failed task errors
    if (responseData['failedTaskErrors'] is Map) {
      final errors = responseData['failedTaskErrors'] as Map;
      for (final entry in errors.entries) {
        failedTaskErrors[entry.key.toString()] = entry.value.toString();
      }
    }

    // Extract server data for conflicts (optional)
    if (responseData['conflicts'] is Map) {
      final conflicts = responseData['conflicts'] as Map;
      for (final entry in conflicts.entries) {
        final taskId = entry.key.toString();
        final data = entry.value;
        if (data is Map) {
          serverData[taskId] = Map<String, dynamic>.from(data);
        }
      }
    }

    // Validate that all tasks are accounted for
    final allTaskIds = tasks.map((t) => t.taskId).toSet();
    final accountedTaskIds = {
      ...successTaskIds,
      ...failedTaskErrors.keys,
    };

    // Handle unaccounted tasks
    for (final taskId in allTaskIds) {
      if (!accountedTaskIds.contains(taskId)) {
        failedTaskErrors[taskId] = 'Task not acknowledged by server';
      }
    }

    return SyncResult(
      successTaskIds: successTaskIds,
      failedTaskErrors: failedTaskErrors,
      serverData: serverData.isEmpty ? null : serverData,
    );
  }

  /// Parses a conflict response.
  SyncResult _parseConflictResponse(
    Map<String, dynamic> responseData,
    List<SyncTask> tasks,
    int statusCode,
  ) {
    final failedTaskErrors = <String, String>{};
    final serverData = <String, Map<String, dynamic>>{};

    // All tasks failed due to conflict
    for (final task in tasks) {
      final conflictData = responseData[task.taskId] as Map?;
      if (conflictData != null) {
        serverData[task.taskId] = Map<String, dynamic>.from(conflictData);
        failedTaskErrors[task.taskId] = 'Conflict detected (HTTP $statusCode)';
      } else {
        failedTaskErrors[task.taskId] = 'Conflict detected (HTTP $statusCode)';
      }
    }

    return SyncResult(
      successTaskIds: {},
      failedTaskErrors: failedTaskErrors,
      serverData: serverData.isEmpty ? null : serverData,
    );
  }

  /// Creates a retryable error result.
  SyncResult _createRetryableErrorResult(List<SyncTask> tasks, int statusCode) {
    final errors = <String, String>{};
    for (final task in tasks) {
      errors[task.taskId] = 'Server error (HTTP $statusCode)';
    }
    return SyncResult.allFailed(errors);
  }

  /// Creates a non-retryable error result.
  SyncResult _createNonRetryableErrorResult(
    List<SyncTask> tasks,
    int statusCode,
    Map<String, dynamic>? responseData,
  ) {
    final errors = <String, String>{};
    final message = responseData?['message']?.toString() ??
        'Request failed (HTTP $statusCode)';
    for (final task in tasks) {
      errors[task.taskId] = message;
    }
    return SyncResult.allFailed(errors, permanent: _isPermanent(statusCode));
  }

  /// Client errors that will fail the same way on every retry go straight
  /// to the dead-letter queue. Auth (401/403), timeout (408), too-early (425)
  /// and rate-limit (429) responses can succeed later, so they are retried.
  static bool _isPermanent(int statusCode) =>
      statusCode >= 400 &&
      statusCode < 500 &&
      !const {401, 403, 408, 425, 429}.contains(statusCode);

  /// Creates a network error result.
  SyncResult _createNetworkErrorResult(
    List<SyncTask> tasks,
    http.ClientException error,
  ) {
    final errors = <String, String>{};
    for (final task in tasks) {
      errors[task.taskId] = 'Network error: ${error.message}';
    }
    return SyncResult.allFailed(errors);
  }

  /// Creates a validation error result.
  SyncResult _createValidationErrorResult(
    List<SyncTask> tasks,
    String message,
  ) {
    final errors = <String, String>{};
    for (final task in tasks) {
      errors[task.taskId] = message;
    }
    return SyncResult.allFailed(errors);
  }

  /// Creates an unknown error result.
  SyncResult _createUnknownErrorResult(List<SyncTask> tasks, Object error) {
    final errors = <String, String>{};
    for (final task in tasks) {
      errors[task.taskId] = 'Unknown error: $error';
    }
    return SyncResult.allFailed(errors);
  }
}

