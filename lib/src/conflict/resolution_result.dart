/// Result of a conflict resolution operation.
///
/// Indicates how a conflict was resolved and what action should be taken.
class ResolutionResult {
  /// The resolved payload to use for retry or final sync.
  final Map<String, dynamic> resolvedPayload;

  /// Whether the task should be retried with the resolved payload.
  final bool shouldRetry;

  /// Whether the task should be aborted (marked as failed, non-retryable).
  final bool shouldAbort;

  /// Source of the resolution (which data was used).
  final ResolutionSource resolutionSource;

  /// Optional error message if resolution failed.
  final String? errorMessage;

  /// Creates a [ResolutionResult] with the given parameters.
  const ResolutionResult({
    required this.resolvedPayload,
    required this.shouldRetry,
    required this.shouldAbort,
    required this.resolutionSource,
    this.errorMessage,
  });

  /// Creates a result that indicates retry with resolved payload.
  factory ResolutionResult.retry(
    Map<String, dynamic> payload,
    ResolutionSource source,
  ) {
    return ResolutionResult(
      resolvedPayload: payload,
      shouldRetry: true,
      shouldAbort: false,
      resolutionSource: source,
    );
  }

  /// Creates a result that indicates the task should be marked as synced.
  factory ResolutionResult.accept(Map<String, dynamic> payload) {
    return ResolutionResult(
      resolvedPayload: payload,
      shouldRetry: false,
      shouldAbort: false,
      resolutionSource: ResolutionSource.server,
    );
  }

  /// Creates a result that indicates the task should be aborted.
  factory ResolutionResult.abort(String errorMessage) {
    return ResolutionResult(
      resolvedPayload: {},
      shouldRetry: false,
      shouldAbort: true,
      resolutionSource: ResolutionSource.client,
      errorMessage: errorMessage,
    );
  }
}

/// Source of data used in conflict resolution.
enum ResolutionSource {
  /// Resolution used server data.
  server,

  /// Resolution used client/local data.
  client,

  /// Resolution merged data from both sources.
  merged,
}

