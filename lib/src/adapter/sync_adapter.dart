import '../core/sync_task.dart';
import '../core/sync_result.dart';

/// Abstract interface for syncing tasks to a remote server.
///
/// Implementations must explicitly confirm which taskIds succeeded
/// in the [SyncResult] to enable partial success handling.
abstract class SyncAdapter {
  /// Syncs a batch of tasks to the server.
  ///
  /// The server must explicitly confirm which taskIds succeeded
  /// by returning them in [SyncResult.successTaskIds].
  ///
  /// Tasks that failed should be returned in [SyncResult.failedTaskErrors]
  /// with their corresponding error messages.
  ///
  /// This method should handle network errors gracefully and return
  /// appropriate error information in the result.
  Future<SyncResult> syncBatch(List<SyncTask> tasks);
}
