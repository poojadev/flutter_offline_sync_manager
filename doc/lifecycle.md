# Sync Lifecycle

This document explains how sync tasks move through their lifecycle and how the engine handles different scenarios.

## Task States

### Pending
- Task is queued and waiting to be synced
- Created when `enqueue()` is called
- Persisted to Hive immediately

### Syncing
- Task is currently being sent to the server
- Marked BEFORE network call (crash-safe)
- If app crashes here, task will be recovered on restart

### Synced
- Server confirmed successful sync
- Task can be cleaned up (optional)
- Dirty fields are cleared (if using dirty tracking)

### Failed
- Sync failed (network error, server error, etc.)
- Retry count is incremented
- May be retried based on retry policy

## State Transitions

```
enqueue() → [Pending]
                ↓
         sync() called
                ↓
         [Syncing] → network call
                ↓
         ┌───────┴───────┐
         ↓               ↓
    [Synced]        [Failed]
                           ↓
                    retry scheduled
                           ↓
                    [Syncing] → ...
```

## Foreground Sync

### Manual Sync
```dart
await syncManager.sync();
```

**Behavior:**
- Fetches pending tasks in batches
- Checks connectivity (if connectivity service provided)
- Marks tasks as syncing
- Calls adapter
- Updates task states based on result

### Auto-Sync Triggers

Auto-sync can be enabled to trigger automatically:

```dart
syncManager.enableAutoSync();
```

**Triggers:**
- Network becomes available
- App resumes from background

**Safety:**
- Only syncs when online (if connectivity service provided)
- Respects single-flight pattern
- No duplicate syncs

## Resume Behavior

When the app resumes from background:

1. Auto-sync triggers (if enabled)
2. Connectivity is checked
3. Pending tasks are synced
4. Stuck "syncing" tasks are reset to "pending" (crash recovery)

## Retry Behavior

### When Retries Happen

Tasks are retried when:
- Sync fails (network error, server error)
- Retry count hasn't exceeded max retries
- Auto-sync is enabled (for automatic retries)

### Retry Backoff

Retries use exponential backoff:

```
Retry 1: 2 seconds
Retry 2: 4 seconds
Retry 3: 8 seconds
Retry 4: 16 seconds
...
Max delay: 5 minutes (configurable)
```

**Why Backoff?**
- Prevents sync storms
- Reduces server load
- Respects network conditions

### Retry Exhaustion

When max retries are exceeded:
- Task stays in "failed" state
- No more automatic retries
- Can be manually retried by calling `sync()`
- Task is not deleted (preserves data)

## Conflict Handling

When a conflict is detected:

1. Task is NOT marked as failed immediately
2. Conflict is detected by `ConflictDetector`
3. Conflict is resolved by `ConflictResolver`
4. Resolved payload is retried
5. If resolution fails, task is marked as failed

**Important:** Conflicts don't increment retry count until resolution fails.

## Background Sync Lifecycle

Background sync follows the same lifecycle but:
- Runs in a separate isolate
- Reinitializes Hive in background isolate
- Uses same sync logic (single-flight, retry, conflicts)
- Best-effort (OS may not execute)

See [Background Sync](background_sync.md) for details.

## Error Handling

### Network Errors
- Marked as retryable
- Retried with backoff
- Task stays in queue

### Server Errors (5xx)
- Marked as retryable
- Retried with backoff
- Task stays in queue

### Client Errors (4xx)
- Marked as non-retryable (except 409/412 conflicts)
- Task marked as failed
- Requires manual intervention

### Validation Errors
- Marked as non-retryable
- Task marked as failed
- Payload needs to be fixed

## Cleanup

Tasks are **never automatically deleted**. This ensures:
- Data is never lost
- Failed tasks can be inspected
- Manual cleanup is possible

To clean up synced tasks:
```dart
// Custom cleanup logic
final tasks = await store.getPendingTasks(1000);
for (final task in tasks) {
  if (task.status == SyncStatus.synced) {
    // Remove from store if desired
  }
}
```

