/// Policy for determining retry delays using exponential backoff.
///
/// Prevents infinite retries and sync storms by implementing
/// exponential backoff with a maximum retry cap.
class RetryPolicy {
  /// Maximum number of retry attempts allowed.
  final int maxRetries;

  /// Base delay duration for the first retry.
  final Duration baseDelay;

  /// Maximum delay duration (caps the exponential growth).
  final Duration maxDelay;

  /// Creates a [RetryPolicy] with the given parameters.
  const RetryPolicy({
    this.maxRetries = 5,
    this.baseDelay = const Duration(seconds: 2),
    this.maxDelay = const Duration(minutes: 5),
  });

  /// Creates a [RetryPolicy] with default values.
  factory RetryPolicy.defaults() {
    return const RetryPolicy();
  }

  /// Calculates the delay for the next retry attempt.
  ///
  /// Returns the delay duration for the given [retryCount], or null
  /// if the maximum number of retries has been exceeded.
  ///
  /// Uses exponential backoff: baseDelay * 2^(retryCount - 1)
  /// Capped at [maxDelay].
  Duration? nextDelay(int retryCount) {
    if (retryCount >= maxRetries) {
      return null; // Retries exhausted
    }

    // Exponential backoff: baseDelay * 2^(retryCount)
    final exponentialDelay = baseDelay * (1 << retryCount);

    // Cap at maxDelay
    if (exponentialDelay > maxDelay) {
      return maxDelay;
    }

    return exponentialDelay;
  }

  /// Checks if a task with the given retry count should be retried.
  bool shouldRetry(int retryCount) {
    return retryCount < maxRetries;
  }
}

