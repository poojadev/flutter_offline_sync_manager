import 'dart:math';

/// Policy for determining retry delays using exponential backoff.
///
/// Prevents infinite retries and sync storms by implementing
/// exponential backoff with a maximum retry cap and optional jitter.
class RetryPolicy {
  /// Maximum number of retry attempts allowed.
  final int maxRetries;

  /// Base delay duration for the first retry.
  final Duration baseDelay;

  /// Maximum delay duration (caps the exponential growth).
  final Duration maxDelay;

  /// Random jitter applied to backoff delays, between 0 and 1.
  ///
  /// A value of `0.2` spreads each delay randomly by ±20%, so many devices
  /// coming back online at once don't retry in lockstep. Defaults to 0.
  final double jitter;

  /// Source of randomness for [jitter]. Defaults to a shared [Random].
  final Random? random;

  static final Random _sharedRandom = Random();

  /// Creates a [RetryPolicy] with the given parameters.
  const RetryPolicy({
    this.maxRetries = 5,
    this.baseDelay = const Duration(seconds: 2),
    this.maxDelay = const Duration(minutes: 5),
    this.jitter = 0.0,
    this.random,
  }) : assert(jitter >= 0 && jitter <= 1);

  /// Creates a [RetryPolicy] with default values.
  factory RetryPolicy.defaults() {
    return const RetryPolicy();
  }

  /// Calculates the delay for the next retry attempt.
  ///
  /// Returns the delay duration for the given [retryCount], or null
  /// if the maximum number of retries has been exceeded.
  ///
  /// Uses exponential backoff: baseDelay * 2^retryCount, capped at
  /// [maxDelay]. Jitter is not applied; see [backoffFor].
  Duration? nextDelay(int retryCount) {
    if (retryCount >= maxRetries) {
      return null; // Retries exhausted
    }
    return _exponential(retryCount);
  }

  /// Backoff to wait after the [failureCount]-th consecutive failure
  /// (1-based), including jitter.
  ///
  /// The first failure waits [baseDelay], the second twice that, and so on,
  /// capped at [maxDelay].
  Duration backoffFor(int failureCount) {
    final exponent = failureCount < 1 ? 0 : failureCount - 1;
    final delay = _exponential(exponent);
    if (jitter == 0) return delay;
    final factor =
        1 + ((random ?? _sharedRandom).nextDouble() * 2 - 1) * jitter;
    return Duration(microseconds: (delay.inMicroseconds * factor).round());
  }

  Duration _exponential(int exponent) {
    // Cap the shift to avoid overflow for very large retry counts.
    final shift = exponent.clamp(0, 30);
    final exponentialDelay = baseDelay * (1 << shift);
    return exponentialDelay > maxDelay ? maxDelay : exponentialDelay;
  }

  /// Checks if a task with the given retry count should be retried.
  bool shouldRetry(int retryCount) {
    return retryCount < maxRetries;
  }
}
