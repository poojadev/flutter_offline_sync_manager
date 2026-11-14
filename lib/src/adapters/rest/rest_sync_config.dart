/// Configuration for REST sync adapter.
///
/// Example usage:
/// ```dart
/// final config = RestSyncConfig(
///   endpoint: 'https://api.example.com/sync',
///   headersProvider: () => {'Authorization': 'Bearer $token'},
/// );
/// ```
class RestSyncConfig {
  /// Base URL for the sync endpoint.
  ///
  /// Example: 'https://api.example.com/sync'
  final String endpoint;

  /// Function that provides HTTP headers for each request.
  ///
  /// Called before each sync request to get current headers
  /// (useful for dynamic auth tokens).
  final Map<String, String> Function()? headersProvider;

  /// Request timeout duration.
  final Duration timeout;

  /// Function to determine if an HTTP status code indicates a conflict.
  ///
  /// Default: 409 (Conflict) and 412 (Precondition Failed)
  final bool Function(int statusCode) isConflictStatusCode;

  /// Function to determine if an HTTP status code is retryable.
  ///
  /// Default: 5xx (server errors) and 408 (Request Timeout)
  final bool Function(int statusCode) isRetryableStatusCode;

  /// Optional hook called before sending each task.
  ///
  /// Can be used for logging, transformation, etc.
  /// Must NOT mutate the task or throw exceptions.
  final void Function(Map<String, dynamic> taskData)? beforeSend;

  /// Optional hook called after receiving response.
  ///
  /// Can be used for logging, validation, etc.
  /// Must NOT throw exceptions.
  final void Function(Map<String, dynamic> response)? afterResponse;

  /// Creates a [RestSyncConfig] with the given parameters.
  RestSyncConfig({
    required this.endpoint,
    this.headersProvider,
    this.timeout = const Duration(seconds: 30),
    bool Function(int)? isConflictStatusCode,
    bool Function(int)? isRetryableStatusCode,
    this.beforeSend,
    this.afterResponse,
  })  : isConflictStatusCode =
            isConflictStatusCode ?? ((code) => code == 409 || code == 412),
        isRetryableStatusCode =
            isRetryableStatusCode ?? ((code) => code >= 500 || code == 408);

  /// Creates a [RestSyncConfig] with default values.
  factory RestSyncConfig.defaults(String endpoint) {
    return RestSyncConfig(endpoint: endpoint);
  }
}
