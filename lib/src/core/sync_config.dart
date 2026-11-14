import '../conflict/conflict_strategy.dart';
import '../conflict/conflict_resolution.dart';
import '../resilience/circuit_breaker.dart';

/// Configuration for the offline sync manager.
class SyncConfig {
  /// Maximum number of tasks to sync in a single batch.
  final int batchSize;

  /// Maximum number of retry attempts for a failed task.
  ///
  /// Used to build the default [RetryPolicy] when none is passed to
  /// [OfflineSyncManager]. An explicit `retryPolicy` takes precedence.
  final int maxRetries;

  /// Strategy for resolving conflicts between local and server data.
  final ConflictStrategy conflictStrategy;

  /// Custom conflict resolver (used when conflictStrategy is [ConflictStrategy.custom]).
  final ConflictResolver? customConflictResolver;

  /// Whether consecutive changes to the same entity are merged into a single
  /// task before they reach the server (queue compaction).
  ///
  /// With compaction on:
  /// - create + update → one create with the merged payload
  /// - update + update → one update with the merged payload
  /// - update + delete → one delete
  /// - create + delete (never sent) → nothing is sent at all
  ///
  /// Tasks that are already in flight are never merged into.
  final bool coalesceOperations;

  /// Maximum number of batches processed by a single [OfflineSyncManager.sync]
  /// call. The queue is drained batch by batch until it is empty, a batch
  /// fails, or this limit is hit.
  final int maxBatchesPerSync;

  /// Tasks older than this are moved to the dead-letter queue instead of
  /// being sent. `null` (the default) means tasks never expire.
  final Duration? taskTimeToLive;

  /// How long synced tasks are kept in the store before being purged.
  ///
  /// The default, [Duration.zero], removes a task as soon as the server
  /// confirms it, which keeps the store from growing forever.
  final Duration syncedTaskRetention;

  /// Optional circuit breaker that pauses syncing after repeated batch
  /// failures, so a struggling backend is not hammered. `null` disables it.
  final CircuitBreakerConfig? circuitBreaker;

  /// When auto-sync is enabled, automatically sync this long after the most
  /// recent [OfflineSyncManager.enqueue] call (debounced). `null` (the
  /// default) disables sync-on-enqueue.
  final Duration? syncOnEnqueueDebounce;

  /// Creates a [SyncConfig] with the given parameters.
  const SyncConfig({
    this.batchSize = 10,
    this.maxRetries = 5,
    this.conflictStrategy = ConflictStrategy.lastWriteWins,
    this.customConflictResolver,
    this.coalesceOperations = true,
    this.maxBatchesPerSync = 20,
    this.taskTimeToLive,
    this.syncedTaskRetention = Duration.zero,
    this.circuitBreaker,
    this.syncOnEnqueueDebounce,
  })  : assert(batchSize > 0),
        assert(maxBatchesPerSync > 0);

  /// Creates a [SyncConfig] with default values.
  factory SyncConfig.defaults() {
    return const SyncConfig();
  }
}
