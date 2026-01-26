/// Represents the result of a batch sync operation.
///
/// The server must explicitly confirm which taskIds succeeded.
/// This allows for partial success handling in batch operations.
class SyncResult {
  /// Set of taskIds that were successfully synced to the server.
  final Set<String> successTaskIds;

  /// Map of taskIds to error messages for tasks that failed to sync.
  final Map<String, String> failedTaskErrors;

  /// Optional map of taskIds to server response data.
  ///
  /// This can be used by adapters to provide server data for conflict detection.
  /// Keys are taskIds, values are the server response payloads.
  final Map<String, Map<String, dynamic>>? serverData;

  /// Creates a [SyncResult] with the given success and failure information.
  const SyncResult({
    required this.successTaskIds,
    required this.failedTaskErrors,
    this.serverData,
  });

  /// Creates a [SyncResult] where all tasks succeeded.
  factory SyncResult.allSuccess(List<String> taskIds) {
    return SyncResult(
      successTaskIds: taskIds.toSet(),
      failedTaskErrors: {},
    );
  }

  /// Creates a [SyncResult] where all tasks failed.
  factory SyncResult.allFailed(
    Map<String, String> errors, {
    Map<String, Map<String, dynamic>>? serverData,
  }) {
    return SyncResult(
      successTaskIds: {},
      failedTaskErrors: errors,
      serverData: serverData,
    );
  }

  /// Returns true if all tasks in the batch succeeded.
  bool get isCompleteSuccess => failedTaskErrors.isEmpty;

  /// Returns true if all tasks in the batch failed.
  bool get isCompleteFailure => successTaskIds.isEmpty;

  /// Returns true if the batch had partial success.
  bool get isPartialSuccess =>
      successTaskIds.isNotEmpty && failedTaskErrors.isNotEmpty;
}

