import '../conflict/conflict_strategy.dart';
import '../conflict/conflict_resolution.dart';

/// Configuration for the offline sync manager.
class SyncConfig {
  /// Maximum number of tasks to sync in a single batch.
  final int batchSize;

  /// Maximum number of retry attempts for a failed task.
  final int maxRetries;

  /// Strategy for resolving conflicts between local and server data.
  final ConflictStrategy conflictStrategy;

  /// Custom conflict resolver (used when conflictStrategy is [ConflictStrategy.custom]).
  final ConflictResolver? customConflictResolver;

  /// Creates a [SyncConfig] with the given parameters.
  const SyncConfig({
    this.batchSize = 10,
    this.maxRetries = 3,
    this.conflictStrategy = ConflictStrategy.lastWriteWins,
    this.customConflictResolver,
  });

  /// Creates a [SyncConfig] with default values.
  factory SyncConfig.defaults() {
    return const SyncConfig();
  }
}

