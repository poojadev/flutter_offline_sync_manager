# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-11-14

### Added
- **Queue compaction**: consecutive changes to one entity are merged
  (create+update → create, update+delete → delete, never-sent create+delete → nothing).
  Controlled by `SyncConfig.coalesceOperations` (default `true`).
- **Priorities** (`SyncPriority`) and **cross-entity dependencies**
  (`enqueue(dependsOn: [EntityRef(...)])`).
- **Per-entity FIFO ordering**: an entity's tasks are always sent oldest first.
- **Dead-letter queue** (`SyncStatus.deadLetter`) with `getDeadLetterTasks()`,
  `retryDeadLetter()`, `discardTask()` and `discardDeadLetters()`.
- **Circuit breaker** (`SyncConfig.circuitBreaker`, `CircuitBreakerConfig`).
- **Reactive state**: `state`, `stateStream`, `watchEntity()`, `getEntityStatus()`.
- `sync()` now returns a `SyncReport`; `sync(force: true)` skips backoff, pause
  and the circuit breaker.
- `pause()` / `resume()`, `SyncConfig.taskTimeToLive`,
  `SyncConfig.syncOnEnqueueDebounce`, `SyncConfig.syncedTaskRetention`,
  `SyncConfig.maxBatchesPerSync`.
- `RetryPolicy.jitter` and `RetryPolicy.backoffFor()`.
- `SyncResult.permanentFailureTaskIds`; the REST adapter marks HTTP 4xx
  (except 401/403/408/425/429) as permanent.
- `HiveSyncStore(boxName:, encryptionCipher:)` for per-account queues and
  encryption at rest.
- `InMemorySyncStore`, plus `FakeSyncAdapter` and `FakeConnectivityService`
  in `package:flutter_offline_sync_manager/testing.dart`.
- New debug events (`taskCoalesced`, `taskAnnihilated`, `taskDeadLettered`,
  `taskRevived`, `circuitOpened`, `circuitClosed`, `paused`, `resumed`) and metrics.
- A test suite (51 tests).

### Changed
- Widened dependency ranges to support the latest releases:
  `cloud_firestore >=4.0.0 <8.0.0`, `connectivity_plus >=6.0.0 <8.0.0`.
- **`workmanager` now requires `^0.10.0`** (was `^0.5.2`). Its API changed
  (`NetworkType.notRequired`, `isInDebugMode` removed), so 0.5.x is no
  longer supported. Apps pinning an older `workmanager` must upgrade.
- Source formatted with `dart format`.

### Fixed
- Static analysis warning in the Android background dispatcher
  (returning a `Future` without `await` inside `try`).
- **Automatic retries never ran**: the retry timer was only scheduled while a
  sync was still marked as running, so it was always skipped.
- **Edits made during an in-flight sync could be lost**: the acknowledgment
  for the old payload marked the newer, unsent payload as synced. Tasks now
  carry a `revision` that is checked before completing them.
- **Conflict retries could loop forever**: conflicts now count against the retry budget.
- Failed tasks were retried on the very next sync, ignoring backoff. Each task
  now has its own `nextAttemptAt`.
- `sync()` sent only one batch per call; it now drains the queue.
- `HiveSyncStore.getPendingTasks` applied the limit before sorting, so it did
  not return the oldest tasks first.
- `getDebugSnapshot()` mutated task state and could never count synced tasks.
- `SyncConfig.maxRetries` was ignored.
- Synced tasks were kept forever, so the store grew without bound.

### Migration from 0.1.x
- Custom `SyncStore` implementations must add `getTask`, `getAllTasks` and `deleteTask`.
- `SyncStatus` has a new `deadLetter` value; update exhaustive `switch` statements.
- Synced tasks are now deleted on success. Set `syncedTaskRetention` to keep them.
- `SyncConfig.maxRetries` now drives the default `RetryPolicy`; its default
  changed from 3 to 5 so effective behaviour is unchanged.
- `getPendingTasks` no longer resets `syncing` tasks to `pending`; the manager
  does crash recovery at the start of each sync.
- Existing Hive queues keep working: the new fields have defaults.

## [0.1.2] - 2026-01-26

### Fixed
- Corrected README installation instructions
- Clarified backend dependency usage (Firestore, REST/GraphQL)
- Fixed example app dependencies
- No runtime or API changes

## [0.1.1] - 2026-01-26

### Fixed
- Relaxed dependency constraints for backend SDKs
    - `cloud_firestore: >=4.0.0 <6.0.0`
    - `http: >=0.13.0 <2.0.0`
- Fixed dependency resolution issues in consuming apps
- No API changes

## [0.1.0] - 2026-01-26

### Added
- Initial release
- Offline-first sync engine with crash-safety and restart-safety
- Background sync, retry logic, conflict resolution
- REST, Firestore, and GraphQL adapters
