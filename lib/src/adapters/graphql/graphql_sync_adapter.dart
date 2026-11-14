import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/sync_task.dart';
import '../../core/sync_result.dart';
import 'graphql_sync_config.dart';
import '../../adapter/sync_adapter.dart';

/// GraphQL sync adapter implementation.
///
/// Syncs tasks to a GraphQL API using mutations.
///
/// Server Contract:
/// - Endpoint: POST {endpoint}
/// - Request body: JSON with 'query' and 'variables'
/// - Mutation should accept:
///   - taskId: string
///   - entityType: string
///   - entityId: string
///   - operation: string
///   - payload: object
///   - updatedAt: string
/// - Response: JSON with 'data' containing:
///   - successTaskIds: array of strings (for batch mutations)
///   - failedTaskErrors: object mapping taskId to error
///   - conflicts: optional object mapping taskId to server data
///
/// Example usage:
/// ```dart
/// final adapter = GraphQLSyncAdapter(
///   config: GraphQLSyncConfig(
///     endpoint: 'https://api.example.com/graphql',
///     mutationBuilder: (task) => '''
///       mutation SyncTask(\$input: SyncTaskInput!) {
///         syncTask(input: \$input) {
///           success
///           error
///         }
///       }
///     ''',
///     headersProvider: () => {'Authorization': 'Bearer $token'},
///   ),
/// );
/// ```
class GraphQLSyncAdapter implements SyncAdapter {
  final GraphQLSyncConfig _config;

  /// Creates a [GraphQLSyncAdapter] with the given configuration.
  GraphQLSyncAdapter({required GraphQLSyncConfig config}) : _config = config;

  @override
  Future<SyncResult> syncBatch(List<SyncTask> tasks) async {
    if (tasks.isEmpty) {
      return const SyncResult(
        successTaskIds: {},
        failedTaskErrors: {},
      );
    }

    // For batch operations, we can either:
    // 1. Send individual mutations (simpler, more flexible)
    // 2. Send a single batch mutation (more efficient, requires server support)
    // We'll use individual mutations for maximum compatibility

    final allSuccessTaskIds = <String>{};
    final allFailedTaskErrors = <String, String>{};
    final allServerData = <String, Map<String, dynamic>>{};

    for (final task in tasks) {
      try {
        final result = await _syncSingleTask(task);
        allSuccessTaskIds.addAll(result.successTaskIds);
        allFailedTaskErrors.addAll(result.failedTaskErrors);
        if (result.serverData != null) {
          allServerData.addAll(result.serverData!);
        }
      } catch (e) {
        allFailedTaskErrors[task.taskId] = 'GraphQL mutation failed: $e';
      }
    }

    return SyncResult(
      successTaskIds: allSuccessTaskIds,
      failedTaskErrors: allFailedTaskErrors,
      serverData: allServerData.isEmpty ? null : allServerData,
    );
  }

  /// Syncs a single task using a GraphQL mutation.
  Future<SyncResult> _syncSingleTask(SyncTask task) async {
    try {
      // Build mutation
      final mutation = _config.mutationBuilder(task);

      // Build variables
      final variables = {
        'input': {
          'taskId': task.taskId,
          'entityType': task.entityType,
          'entityId': task.entityId,
          'operation': task.operation.name,
          'payload': task.payload,
          'updatedAt': task.updatedAt.toIso8601String(),
          if (task.isPartialUpdate) 'isPartialUpdate': true,
        },
      };

      // Build request body
      final requestBody = {
        'query': mutation,
        'variables': variables,
      };

      // Call beforeSend hook
      _config.beforeSend?.call(task, mutation);

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

      // Handle GraphQL errors
      if (responseData.containsKey('errors')) {
        final errors = responseData['errors'] as List;
        final errorMessage = errors.isNotEmpty
            ? errors[0]['message']?.toString() ?? 'GraphQL error'
            : 'GraphQL error';
        return SyncResult.allFailed({task.taskId: errorMessage});
      }

      // Extract data
      final data = responseData['data'] as Map<String, dynamic>?;
      if (data == null) {
        return SyncResult.allFailed({task.taskId: 'No data in response'});
      }

      // Extract results using config functions or defaults
      final successTaskIds = _config.extractSuccessTaskIds?.call(data) ??
          _defaultExtractSuccessTaskIds(data, task.taskId);

      final failedTaskErrors = _config.extractFailedTaskErrors?.call(data) ??
          _defaultExtractFailedTaskErrors(data, task.taskId);

      final serverData = _config.extractServerData?.call(data) ??
          _defaultExtractServerData(data, task.taskId);

      return SyncResult(
        successTaskIds: successTaskIds.toSet(),
        failedTaskErrors: failedTaskErrors,
        serverData: serverData.isEmpty ? null : serverData,
      );
    } on http.ClientException catch (e) {
      return SyncResult.allFailed({
        task.taskId: 'Network error: ${e.message}',
      });
    } on FormatException catch (e) {
      return SyncResult.allFailed({
        task.taskId: 'Invalid response format: $e',
      });
    } catch (e) {
      return SyncResult.allFailed({
        task.taskId: 'Unknown error: $e',
      });
    }
  }

  /// Default extraction of success task IDs.
  List<String> _defaultExtractSuccessTaskIds(
    Map<String, dynamic> data,
    String taskId,
  ) {
    if (data['successTaskIds'] is List) {
      return (data['successTaskIds'] as List)
          .map((id) => id.toString())
          .toList();
    }
    // If mutation returns success field, check it
    if (data['syncTask'] is Map) {
      final syncTask = data['syncTask'] as Map;
      if (syncTask['success'] == true) {
        return [taskId];
      }
    }
    return [];
  }

  /// Default extraction of failed task errors.
  Map<String, String> _defaultExtractFailedTaskErrors(
    Map<String, dynamic> data,
    String taskId,
  ) {
    if (data['failedTaskErrors'] is Map) {
      final errors = data['failedTaskErrors'] as Map;
      return {
        for (final entry in errors.entries)
          entry.key.toString(): entry.value.toString()
      };
    }
    // If mutation returns error field, use it
    if (data['syncTask'] is Map) {
      final syncTask = data['syncTask'] as Map;
      if (syncTask['error'] != null) {
        return {taskId: syncTask['error'].toString()};
      }
    }
    return {};
  }

  /// Default extraction of server data for conflicts.
  Map<String, Map<String, dynamic>> _defaultExtractServerData(
    Map<String, dynamic> data,
    String taskId,
  ) {
    if (data['conflicts'] is Map) {
      final conflicts = data['conflicts'] as Map;
      return {
        for (final entry in conflicts.entries)
          entry.key.toString(): Map<String, dynamic>.from(entry.value as Map)
      };
    }
    // If mutation returns conflict data, use it
    if (data['syncTask'] is Map) {
      final syncTask = data['syncTask'] as Map;
      if (syncTask['conflictData'] is Map) {
        return {
          taskId: Map<String, dynamic>.from(syncTask['conflictData'] as Map)
        };
      }
    }
    return {};
  }
}
