# Conflict Resolution

This document explains how conflicts are detected and resolved in `flutter_offline_sync_manager`.

## When Conflicts Occur

Conflicts happen when:
- Local data was modified offline
- Server data changed independently (by another client or admin)
- Same entity was edited in two places simultaneously

## Conflict Detection

The `ConflictDetector` identifies conflicts by checking:

1. **Explicit conflict flags** in server response (`_conflict: true`)
2. **Version mismatch** (server version ≠ local version)
3. **HTTP status codes** (409 Conflict, 412 Precondition Failed)
4. **Error messages** containing "conflict", "version mismatch", etc.

### Default Detection

The default `DefaultConflictDetector` checks:
- Server response for conflict flags
- Version fields (`version`, `etag`, `_version`, `_etag`)
- Timestamp comparison (if available)
- Error message patterns

### Custom Detection

You can provide a custom detector:

```dart
class MyConflictDetector implements ConflictDetector {
  @override
  ConflictDetectedResult detect({
    required SyncTask localTask,
    Map<String, dynamic>? serverResponse,
    String? errorMessage,
  }) {
    // Your custom detection logic
  }
}
```

## Conflict Resolution Strategies

### Last Write Wins (Default)

Compares timestamps and uses the newer version.

```dart
SyncConfig(
  conflictStrategy: ConflictStrategy.lastWriteWins,
)
```

**Behavior:**
- Compares `updatedAt` timestamps
- Server wins if server timestamp is newer
- Client wins if local timestamp is newer or equal

**Use When:**
- Timestamps are reliable
- Simple resolution is acceptable
- Most common use case

### Server Wins

Always accepts server data, discarding local changes.

```dart
SyncConfig(
  conflictStrategy: ConflictStrategy.serverWins,
)
```

**Behavior:**
- Accepts server data immediately
- Marks task as synced
- Local changes are discarded

**Use When:**
- Server is source of truth
- Local changes can be safely discarded
- Admin/system changes take precedence

### Client Wins

Always preserves local changes, retrying with local payload.

```dart
SyncConfig(
  conflictStrategy: ConflictStrategy.clientWins,
)
```

**Behavior:**
- Retries with local payload
- Server data is ignored
- Local changes take precedence

**Use When:**
- Local edits are most important
- User input should never be lost
- Offline-first priority

### Field-Level Merge

Merges dirty client fields with clean server fields.

```dart
SyncConfig(
  conflictStrategy: ConflictStrategy.fieldLevelMerge,
)
```

**Behavior:**
- Starts with server data (base)
- Overlays dirty client fields
- Preserves clean server fields
- Safe, conservative merge

**Use When:**
- Field-level precision is needed
- Want to preserve untouched server fields
- Using dirty tracking

### Custom Resolver

Implement your own resolution logic.

```dart
class MyConflictResolver implements ConflictResolver {
  @override
  ResolutionResult resolve({
    required SyncTask localTask,
    required Map<String, dynamic> serverData,
  }) {
    // Your custom resolution logic
    // Return ResolutionResult.retry(...) or ResolutionResult.accept(...)
  }
}

SyncConfig(
  conflictStrategy: ConflictStrategy.custom,
  customConflictResolver: MyConflictResolver(),
)
```

**Use When:**
- Complex business logic required
- Field-specific rules
- User interaction needed (future)

## Field-Level Conflict Resolution

When using dirty tracking, conflicts are resolved at the **field level**:

1. Only dirty fields are considered for conflict
2. Clean fields from server are preserved
3. Dirty fields from client overwrite server
4. Result is a safe merge

**Example:**
```
Local:  {title: "New", content: "Old"}  (title is dirty)
Server: {title: "Old", content: "New"}  (content changed on server)
Result: {title: "New", content: "New"}  (dirty title wins, clean content preserved)
```

## Resolution Flow

```
Conflict Detected
       ↓
ConflictResolver.resolve()
       ↓
   ┌───┴───┐
   ↓       ↓
Retry   Accept
   ↓       ↓
Update  Mark as
Payload  Synced
```

### Retry Path

If resolution says to retry:
- Task payload is updated with resolved data
- Task status set to pending
- Task will be retried in next sync
- Retry count is NOT incremented (conflict ≠ failure)

### Accept Path

If resolution accepts server data:
- Task is marked as synced
- Server data becomes source of truth
- Dirty fields are cleared (if using dirty tracking)

## Infinite Loop Prevention

To prevent infinite conflict loops:

1. **Retry Policy**: Max retries eventually stops retries
2. **Conflict Check**: If retries exhausted, conflict resolution aborts
3. **Resolution Safety**: Resolvers should produce stable results

**Best Practice:** Ensure your conflict resolver always produces a result that will eventually succeed or fail deterministically.

## Examples

### Example 1: Simple Last-Write-Wins

```dart
final manager = OfflineSyncManager(
  store: store,
  adapter: adapter,
  config: SyncConfig(
    conflictStrategy: ConflictStrategy.lastWriteWins,
  ),
);
```

### Example 2: Field-Level Merge with Dirty Tracking

```dart
final dirtyTracker = DirtyTracker();
await dirtyTracker.initialize();

// Mark fields as dirty
await dirtyTracker.markDirty(
  entityType: 'note',
  entityId: '123',
  fieldPath: 'title',
);

final manager = OfflineSyncManager(
  store: store,
  adapter: adapter,
  dirtyTracker: dirtyTracker,
  config: SyncConfig(
    conflictStrategy: ConflictStrategy.fieldLevelMerge,
  ),
);
```

### Example 3: Custom Resolver

```dart
class PriorityBasedResolver implements ConflictResolver {
  @override
  ResolutionResult resolve({
    required SyncTask localTask,
    required Map<String, dynamic> serverData,
  }) {
    // Check priority field
    final localPriority = localTask.payload['priority'] as int? ?? 0;
    final serverPriority = serverData['priority'] as int? ?? 0;
    
    if (localPriority > serverPriority) {
      return ResolutionResult.retry(localTask.payload, ResolutionSource.client);
    } else {
      return ResolutionResult.accept(serverData);
    }
  }
}
```

## Best Practices

1. **Choose the right strategy** for your use case
2. **Use dirty tracking** for field-level precision
3. **Test conflict scenarios** in your app
4. **Monitor conflicts** using debug inspector
5. **Document your strategy** for your team

## Troubleshooting

### Conflicts Keep Happening

- Check if your resolver produces stable results
- Verify version/conflict detection logic
- Consider using field-level merge

### Too Many Conflicts

- Review your conflict detection (may be too sensitive)
- Consider using `clientWins` if local edits are priority
- Check if multiple clients are editing same entities

### Conflicts Not Detected

- Verify your adapter reports conflicts correctly
- Check conflict detector configuration
- Ensure server sends conflict indicators

