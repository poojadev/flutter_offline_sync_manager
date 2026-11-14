import '../../core/sync_task.dart';

/// Configuration for GraphQL sync adapter.
///
/// Example usage:
/// ```dart
/// final config = GraphQLSyncConfig(
///   endpoint: 'https://api.example.com/graphql',
///   mutationBuilder: (task) => '''
///     mutation SyncTask(\$input: SyncTaskInput!) {
///       syncTask(input: \$input) {
///         success
///         error
///       }
///     }
///   ''',
/// );
/// ```
class GraphQLSyncConfig {
  /// GraphQL endpoint URL.
  final String endpoint;

  /// Function that builds a GraphQL mutation for a single task.
  ///
  /// Should return a GraphQL mutation string with variables.
  /// The mutation should accept a variable of type matching your schema.
  final String Function(SyncTask task) mutationBuilder;

  /// Function that provides HTTP headers for each request.
  ///
  /// Called before each GraphQL request to get current headers
  /// (useful for dynamic auth tokens).
  final Map<String, String> Function()? headersProvider;

  /// Request timeout duration.
  final Duration timeout;

  /// Function to extract success task IDs from GraphQL response.
  ///
  /// Default: Looks for 'successTaskIds' in response data
  final List<String> Function(Map<String, dynamic> responseData)?
      extractSuccessTaskIds;

  /// Function to extract failed task errors from GraphQL response.
  ///
  /// Default: Looks for 'failedTaskErrors' in response data
  final Map<String, String> Function(Map<String, dynamic> responseData)?
      extractFailedTaskErrors;

  /// Function to extract server data for conflicts from GraphQL response.
  ///
  /// Default: Looks for 'conflicts' in response data
  final Map<String, Map<String, dynamic>> Function(
      Map<String, dynamic> responseData)? extractServerData;

  /// Optional hook called before sending each task.
  ///
  /// Can be used for logging, transformation, etc.
  /// Must NOT  mutate the task or throw exceptions.
  final void Function(SyncTask task, String mutation)? beforeSend;

  /// Optional hook called after receiving response.
  ///
  /// Can be used for logging, validation, etc.
  /// Must NOT throw exceptions.
  final void Function(Map<String, dynamic> response)? afterResponse;

  /// Creates a [GraphQLSyncConfig] with the given parameters.
  GraphQLSyncConfig({
    required this.endpoint,
    required this.mutationBuilder,
    this.headersProvider,
    this.timeout = const Duration(seconds: 30),
    this.extractSuccessTaskIds,
    this.extractFailedTaskErrors,
    this.extractServerData,
    this.beforeSend,
    this.afterResponse,
  });
}
