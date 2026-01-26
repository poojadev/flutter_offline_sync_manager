# Frequently Asked Questions

## Data Safety

### Will this package lose my data?

**No.** The package is designed to prevent data loss:

- Tasks are persisted to Hive before any network call
- Tasks are marked as "syncing" BEFORE the network call (crash-safe)
- Tasks are only marked as "synced" after server confirmation
- Failed tasks remain in queue for retry
- Tasks survive app restarts and crashes

### What happens if the app crashes during sync?

Tasks are marked as "syncing" **before** the network call. If the app crashes:
- Tasks remain in "syncing" state
- On restart, "syncing" tasks are reset to "pending"
- Tasks are retried safely (no duplicates)

### What happens if the server is down?

Tasks remain in the queue. When the server comes back online:
- Auto-sync triggers (if enabled)
- Tasks are retried with exponential backoff
- No data is lost

## Offline Behavior

### Does it work offline forever?

**Yes.** Tasks are stored locally and will sync when:
- Network becomes available (if auto-sync enabled)
- App resumes (if auto-sync enabled)
- Manual sync is triggered

There's no time limit on offline storage.

### Will tasks sync automatically when I come back online?

**Yes, if auto-sync is enabled:**

```dart
syncManager.enableAutoSync();
```

This requires a `ConnectivityService` to be provided.

### What if I'm offline for days/weeks?

Tasks remain in the queue indefinitely. They will sync when:
- Network becomes available
- You trigger manual sync
- Background sync runs (best-effort)

## Background Sync

### Does it auto-sync in the background?

**Best-effort, yes.** Background sync is enabled separately:

```dart
backgroundManager.enable();
```

**Important:** Background sync is OS-controlled and not guaranteed:
- Android: Minimum 15-minute intervals
- iOS: OS decides when to run
- May not run if battery is low
- May not run if app isn't used

**Recommendation:** Don't rely solely on background sync. Use foreground sync as primary.

### How often does background sync run?

**It depends:**
- **Android**: At least every 15 minutes (if constraints met)
- **iOS**: OS decides (could be hours or days)

There's no guarantee of frequency.

## Backend Requirements

### Is Firebase required?

**No.** The package is backend-agnostic. You can use:
- REST APIs (via `RestSyncAdapter`)
- Firebase Firestore (via `FirestoreSyncAdapter`)
- GraphQL (via `GraphQLSyncAdapter`)
- Custom backend (implement `SyncAdapter`)

### What does my server need to support?

Your server needs to:
1. Accept batch sync requests
2. Return which tasks succeeded/failed
3. Optionally report conflicts

See adapter documentation for specific requirements.

### Can I use my existing REST API?

**Yes.** Use `RestSyncAdapter` and configure it to match your API:

```dart
final adapter = RestSyncAdapter(
  config: RestSyncConfig(
    endpoint: 'https://your-api.com/sync',
    headersProvider: () => {'Authorization': 'Bearer $token'},
  ),
);
```

## Production Readiness

### Is this production-ready?

**Yes.** The package includes:
- Crash-safety (tasks survive app kills)
- Restart-safety (queue persists)
- Duplication-safety (deterministic IDs)
- Retry logic (exponential backoff)
- Conflict resolution (multiple strategies)
- Error handling (graceful failures)
- Debug tools (observability)

### What are the guarantees?

See the [README.md](../README.md#guarantees) for explicit guarantees:
- No data loss
- No duplication
- Restart-safe
- Backend-agnostic
- OS-compliant

### How do I monitor sync in production?

Use the debug inspector (dev-only, zero overhead when disabled):

```dart
final debugController = SyncDebugController(store: store);
debugController.enable();

debugController.events.listen((event) {
  // Monitor sync events
});

final snapshot = await debugController.getCurrentSnapshot();
// Check metrics, queue state, etc.
```

## Comparison with Alternatives

### Why not just use Firestore offline?

Firestore offline is great, but:
- **Tied to Firebase**: Can't use with other backends
- **No conflict resolution**: Basic last-write-wins only
- **No retry control**: Firestore handles retries internally
- **No field-level tracking**: Syncs entire documents
- **No queue visibility**: Can't inspect what's pending

This package gives you:
- Backend flexibility
- Advanced conflict resolution
- Field-level precision
- Full control and observability

### How does this compare to other sync packages?

**This package focuses on:**
- **Safety first**: Crash-safe, restart-safe, duplication-safe
- **Backend-agnostic**: Works with any backend
- **Field-level precision**: Sync only what changed
- **Production-ready**: Battle-tested patterns

Other packages may:
- Be tied to specific backends
- Not handle crashes well
- Create duplicates
- Lack conflict resolution

## Performance

### Will this slow down my app?

**No.** The package is designed for performance:
- Hive is fast (in-memory with disk persistence)
- Batch operations reduce overhead
- Single-flight prevents duplicate work
- Debug tools have zero overhead when disabled

### How much storage does it use?

Minimal:
- Each task is stored as a Hive object
- Typical task: ~1-5 KB
- 1000 tasks ≈ 1-5 MB

Tasks can be cleaned up after sync (optional).

### Does it use a lot of battery?

**No.** The package:
- Respects battery constraints (if configured)
- Uses exponential backoff (reduces retries)
- Only syncs when online
- Background sync is best-effort (OS-controlled)

## Customization

### Can I customize conflict resolution?

**Yes.** Choose from:
- Built-in strategies (last-write-wins, server-wins, etc.)
- Custom resolver (implement `ConflictResolver`)

### Can I add my own adapter?

**Yes.** Implement the `SyncAdapter` interface:

```dart
class MyCustomAdapter implements SyncAdapter {
  @override
  Future<SyncResult> syncBatch(List<SyncTask> tasks) async {
    // Your implementation
  }
}
```

### Can I customize retry behavior?

**Yes.** Provide a custom `RetryPolicy`:

```dart
final retryPolicy = RetryPolicy(
  maxRetries: 5,
  baseDelay: Duration(seconds: 2),
  maxDelay: Duration(minutes: 5),
);
```

## Troubleshooting

### Tasks are not syncing

Check:
1. Is auto-sync enabled? `syncManager.enableAutoSync()`
2. Is device online? (if connectivity service provided)
3. Are there any errors? Check debug inspector
4. Is adapter configured correctly?

### Too many retries

Check:
1. Retry policy configuration
2. Server error responses
3. Network connectivity
4. Adapter error handling

### Conflicts keep happening

Check:
1. Conflict resolution strategy
2. Version/conflict detection logic
3. Multiple clients editing same entities
4. Consider field-level merge

### Background sync not working

See [Background Sync](background_sync.md) documentation for platform-specific troubleshooting.

## Getting Help

- 📖 Check the [documentation](.)
- 💬 Ask on [GitHub Discussions](https://github.com/yourusername/flutter_offline_sync_manager/discussions)
- 🐛 Report bugs on [GitHub Issues](https://github.com/yourusername/flutter_offline_sync_manager/issues)

