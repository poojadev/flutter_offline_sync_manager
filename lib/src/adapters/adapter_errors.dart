/// Typed errors for adapter implementations.
///
/// These errors help distinguish between retryable and non-retryable failures,
/// enabling better error handling and retry logic.
abstract class AdapterError implements Exception {
  /// Human-readable error message.
  final String message;

  /// Whether this error is retryable.
  ///
  /// Retryable errors (e.g., network timeouts) should be retried.
  /// Non-retryable errors (e.g., authentication failures) should not be retried.
  final bool retryable;

  /// Creates an [AdapterError] with the given message and retryability.
  const AdapterError(this.message, {this.retryable = false});

  @override
  String toString() => message;
}

/// Network-related error (timeout, connection failure, etc.).
///
/// These are typically retryable unless the error indicates a permanent failure.
class NetworkError extends AdapterError {
  /// Original exception that caused this error, if any.
  final Object? originalError;

  /// Creates a [NetworkError].
  const NetworkError(
    super.message, {
    super.retryable = true,
    this.originalError,
  });
}

/// Authentication/authorization error.
///
/// These are typically non-retryable without re-authentication.
class AuthError extends AdapterError {
  /// HTTP status code, if applicable.
  final int? statusCode;

  /// Creates an [AuthError].
  const AuthError(
    super.message, {
    super.retryable = false,
    this.statusCode,
  });
}

/// Validation error (bad request, invalid payload, etc.).
///
/// These are typically non-retryable without fixing the payload.
class ValidationError extends AdapterError {
  /// Field or path that failed validation, if applicable.
  final String? field;

  /// Creates a [ValidationError].
  const ValidationError(
    super.message, {
    super.retryable = false,
    this.field,
  });
}

/// Conflict error (version mismatch, optimistic locking failure, etc.).
///
/// These are typically retryable after conflict resolution.
class ConflictError extends AdapterError {
  /// Server data that conflicts with local data, if available.
  final Map<String, dynamic>? serverData;

  /// Creates a [ConflictError].
  const ConflictError(
    super.message, {
    super.retryable = true,
    this.serverData,
  });
}

/// Unknown or unexpected adapter error.
///
/// Used when the error type cannot be determined.
class UnknownAdapterError extends AdapterError {
  /// Original exception that caused this error, if any.
  final Object? originalError;

  /// Creates an [UnknownAdapterError].
  const UnknownAdapterError(
    super.message, {
    super.retryable = false,
    this.originalError,
  });
}
