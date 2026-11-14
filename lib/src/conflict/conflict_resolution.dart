import '../core/sync_task.dart';
import 'resolution_result.dart';

/// Abstract interface for resolving conflicts between local and server data.
///
/// Implementations must provide deterministic resolution logic that:
/// - Never loses data without explicit strategy
/// - Never creates duplicate tasks
/// - Never causes infinite retry loops
/// - Always produces a valid payload for retry or acceptance
abstract class ConflictResolver {
  /// Resolves a conflict between local task and server data.
  ///
  /// [localTask] is the local task that conflicts with server data.
  /// [serverData] is the current server data that conflicts with local changes.
  ///
  /// Returns [ResolutionResult] indicating:
  /// - The resolved payload to use
  /// - Whether to retry with the resolved payload
  /// - Whether to abort the sync
  /// - The source of the resolution
  ResolutionResult resolve({
    required SyncTask localTask,
    required Map<String, dynamic> serverData,
  });
}
