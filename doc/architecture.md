# Architecture

This document explains the internal architecture and design decisions of `flutter_offline_sync_manager`.

## Core Concepts

### SyncTask

A `SyncTask` represents a single entity that needs to be synchronized with the server.

**Key Properties:**
- `taskId`: Deterministic ID derived from `entityType + entityId + operation`
- `payload`: The data to sync (full or partial)
- `status`: Current state (pending, syncing, failed, synced)
- `retryCount`: Number of retry attempts

**Why Deterministic taskId?**

If the same entity is updated multiple times offline, they should result in the **same taskId**. This ensures:
- Only the latest update is synced (no duplicates)
- Old updates are automatically overwritten
- No manual deduplication needed

Example:
```dart
// First update
enqueue(entityType: 'note', entityId: '123', operation: update, payload: {...})
// taskId = 'note_123_update'

// Second update (overwrites first)
enqueue(entityType: 'note', entityId: '123', operation: update, payload: {...})
// taskId = 'note_123_update' (same!)
```

### SyncQueue (Hive-based)

Tasks are stored in a Hive box using `taskId` as the key. This provides:
- **Persistence**: Survives app restarts
- **Fast lookups**: O(1) access by taskId
- **Crash-safety**: Hive is ACID-compliant

### Single-Flight Sync

Only one sync operation can run at a time. This prevents:
- Race conditions
- Duplicate network requests
- Inconsistent state

If `sync()` is called while a sync is in progress, it waits for the current sync to complete.

### Batch Sync

Tasks are synced in configurable batches (default: 10). This:
- Reduces network overhead
- Handles partial success gracefully
- Respects server batch limits

## Sync Lifecycle

```
[Pending] → [Syncing] → [Synced]
                ↓
            [Failed] → (retry) → [Syncing] → ...
```

1. **Pending**: Task is queued, waiting to sync
2. **Syncing**: Task is being sent to server (marked BEFORE network call for crash-safety)
3. **Synced**: Server confirmed receipt (task can be cleaned up)
4. **Failed**: Sync failed (may retry based on retry policy)

## Crash Safety

### Why Mark as "Syncing" Before Network Call?

If we mark tasks as "syncing" AFTER the network call succeeds:
- App crashes during network call → task stays "pending"
- On restart, task is retried → **duplicate sync**

If we mark tasks as "syncing" BEFORE the network call:
- App crashes during network call → task stays "syncing"
- On restart, "syncing" tasks are reset to "pending" → **safe retry**

### Restart Recovery

On app restart, tasks stuck in "syncing" state are automatically reset to "pending" for retry. This handles crashes gracefully.

## Adapter Pattern

The `SyncAdapter` interface decouples the sync engine from the backend:

```dart
abstract class SyncAdapter {
  Future<SyncResult> syncBatch(List<SyncTask> tasks);
}
```

**Benefits:**
- Backend-agnostic core engine
- Easy to swap backends
- Testable (mock adapters)
- Multiple backend support

**Official Adapters:**
- `RestSyncAdapter` - REST APIs
- `FirestoreSyncAdapter` - Firebase Firestore
- `GraphQLSyncAdapter` - GraphQL APIs

## Dirty Tracking

Field-level dirty tracking allows syncing only changed fields:

1. Developer marks fields as dirty: `dirtyTracker.markDirty(entityType, entityId, 'title')`
2. On enqueue, only dirty fields are included in payload
3. Server receives partial update
4. On success, dirty fields are cleared

**Benefits:**
- Reduced network usage
- Faster syncs
- Precise conflict resolution (field-level)

## Conflict Resolution

Conflicts occur when:
- Local data was modified offline
- Server data changed independently
- Same entity edited in two places

**Resolution Flow:**
1. Server reports conflict (version mismatch, 409, etc.)
2. `ConflictDetector` identifies conflict
3. `ConflictResolver` resolves using configured strategy
4. Resolved payload is retried

**Strategies:**
- `lastWriteWins` - Timestamp comparison
- `serverWins` - Accept server data
- `clientWins` - Retry with local data
- `fieldLevelMerge` - Merge dirty fields with clean server fields
- `custom` - Your own resolver

## Background Sync

Background sync is **best-effort** and OS-controlled:

- **Android**: Uses WorkManager (minimum 15-minute intervals)
- **iOS**: Uses background fetch (OS decides when to run)

**Limitations:**
- OS may not execute background work
- Frequency is not guaranteed
- Battery and network constraints apply

**Recommendation:** Don't rely solely on background sync. Use foreground sync as primary, background as supplement.

## Debug Inspector

The debug inspector provides observability without affecting production:

- **Events**: Stream of sync lifecycle events
- **Metrics**: Counters and timers
- **Snapshot**: Current queue state

**Zero Overhead When Disabled:**
- Debug mode is OFF by default
- When disabled, no events are emitted
- No performance impact

## Why Hive?

Hive was chosen for storage because:
- **Fast**: In-memory performance with disk persistence
- **Type-safe**: Strong typing with adapters
- **Lightweight**: No native dependencies
- **ACID**: Crash-safe writes
- **Flutter-friendly**: Works well with Flutter isolates

## Thread Safety

The sync engine is **not thread-safe** by design:
- Flutter is single-threaded (Dart isolate)
- Background sync runs in separate isolate (reinitializes Hive)
- Single-flight pattern prevents concurrent syncs

If you need multi-threaded access, use proper synchronization primitives.

