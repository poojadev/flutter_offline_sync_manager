# flutter_offline_sync_manager

**Offline-first, conflict-safe sync engine for Flutter**

[![pub package](https://img.shields.io/pub/v/flutter_offline_sync_manager.svg)](https://pub.dev/packages/flutter_offline_sync_manager)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A production-grade Flutter package that handles offline data synchronization with crash-safety, restart-safety, and duplication-safety. Works with any backend (REST, Firebase, GraphQL, or custom).

---

## Why This Package Exists

Offline sync is **hard**. Most solutions fail because they:

- ❌ **Lose data** when the app crashes mid-sync
- ❌ **Create duplicates** when the same entity is updated multiple times
- ❌ **Retry infinitely** causing sync storms
- ❌ **Overwrite clean data** during conflict resolution
- ❌ **Don't survive app restarts** losing queued changes

This package solves all of these problems with a **deterministic, crash-safe queue** that guarantees:

- ✅ **Zero data loss** — tasks persist even if the app is killed
- ✅ **Zero duplication** — deterministic task IDs prevent duplicates
- ✅ **Smart retries** — exponential backoff prevents sync storms
- ✅ **Safe conflicts** — field-level resolution preserves clean data
- ✅ **Restart-safe** — queue survives app restarts and crashes

---

## Features

### Core Engine
- **Persistent sync queue** using Hive (survives app restarts), optionally **encrypted at rest**
- **Deterministic task IDs** prevent duplicate syncs
- **Queue compaction**: create + update + update becomes a single request, and create + delete never touches the network *(new in 0.2)*
- **Edit-while-syncing safety**: an edit made during an in-flight request is never marked as synced by the older acknowledgment *(new in 0.2)*
- **Single-flight sync** prevents parallel execution
- **Batch sync** with partial success handling; one `sync()` drains the whole queue

### Ordering & Scheduling *(new in 0.2)*
- **Priorities** (`low`, `normal`, `high`, `critical`)
- **Per-entity FIFO**: an update never overtakes the create it depends on
- **Cross-entity dependencies**: hold a `comment` until its `post` is synced

### Automation & Reliability
- **Auto-retry** with per-task exponential backoff and optional jitter
- **Dead-letter queue** for permanently failing tasks: inspect, retry or discard them *(new in 0.2)*
- **Circuit breaker** stops hammering a struggling backend *(new in 0.2)*
- **Task time-to-live**, **pause / resume**, and debounced **sync-on-enqueue** *(new in 0.2)*
- **Connectivity awareness** (only syncs when online)
- **App lifecycle hooks** (syncs on resume)
- **Background sync** (best-effort, OS-compliant)

### Conflict Resolution
- **Multiple strategies** (last-write-wins, server-wins, client-wins, field-merge)
- **Field-level dirty tracking** (sync only changed fields)
- **Safe merging** (never overwrites clean data)
- **Custom resolvers** for complex scenarios

### Developer Experience
- **Reactive UI state**: `stateStream` and per-entity `watchEntity()` for "pending upload" badges, no debug mode needed *(new in 0.2)*
- **`SyncReport`** returned from every `sync()` *(new in 0.2)*
- **Testing kit**: `InMemorySyncStore`, `FakeSyncAdapter`, `FakeConnectivityService` *(new in 0.2)*
- **Debug inspector** (dev-only, zero production overhead)
- **Sync metrics** (observability without logging)
- **Event stream** (monitor sync lifecycle)

### Backend Support
- **REST adapter** (ready-to-use)
- **Firebase Firestore adapter** (ready-to-use)
- **GraphQL adapter** (ready-to-use)
- **Custom adapters** (easy to implement)

---

## Quick Start (10 minutes)

### 1. Add Dependency

```yaml
dependencies:
  flutter_offline_sync_manager: ^0.2.0
  hive: ^2.2.3
  hive_flutter: ^1.1.0
```

**Backend SDK Dependencies:**

This package includes adapters for Firestore, REST, and GraphQL. If you use any of these adapters, you must also add the corresponding backend SDK to your app's `pubspec.yaml`:

- **For Firestore adapter:** Add `cloud_firestore` (compatible with `>=4.0.0 <6.0.0`)
- **For REST/GraphQL adapters:** Add `http` (compatible with `>=0.13.0 <2.0.0`)

Example for Firestore usage:
```yaml
dependencies:
  flutter_offline_sync_manager: ^0.2.0
  hive: ^2.2.3
  hive_flutter: ^1.1.0
  cloud_firestore: ^5.0.0  # Your app's version
```

The package uses wide version constraints to ensure compatibility with your app's backend SDK versions.

### 2. Initialize Hive

```dart
import 'package:hive_flutter/hive_flutter.dart';

void main() async {
  await Hive.initFlutter();
  runApp(MyApp());
}
```

### 3. Create Sync Adapter

**REST Adapter:**
```dart
import 'package:flutter_offline_sync_manager/flutter_offline_sync_manager.dart';

final adapter = RestSyncAdapter(
  config: RestSyncConfig(
    endpoint: 'https://api.example.com/sync',
    headersProvider: () => {'Authorization': 'Bearer $token'},
  ),
);
```

**Firestore Adapter:**
```dart
import 'package:flutter_offline_sync_manager/flutter_offline_sync_manager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

final adapter = FirestoreSyncAdapter(
  firestore: FirebaseFirestore.instance,
  config: FirestoreSyncConfig(
    collectionPath: 'journal_entries',
    versionField: 'version',
  ),
);
```

### 4. Create Sync Manager

```dart
import 'package:hive/hive.dart';
import 'package:flutter_offline_sync_manager/flutter_offline_sync_manager.dart';

// Create store
final store = HiveSyncStore();
await store.initialize();

// Create manager
final syncManager = OfflineSyncManager(
  store: store,
  adapter: adapter,
);

// Enable auto-sync (optional)
final connectivityService = DefaultConnectivityService();
syncManager.enableAutoSync();
```

### 5. Enqueue & Sync

```dart
// Enqueue a task
await syncManager.enqueue(
  entityType: 'note',
  entityId: 'note-123',
  operation: SyncOperation.update,
  payload: {
    'title': 'Updated title',
    'content': 'Updated content',
  },
);

// Sync manually (or let auto-sync handle it)
await syncManager.sync();
```

---

## Basic Example

```dart
import 'package:flutter/material.dart';
import 'package:flutter_offline_sync_manager/flutter_offline_sync_manager.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() async {
  await Hive.initFlutter();
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late OfflineSyncManager syncManager;

  @override
  void initState() {
    super.initState();
    _initializeSync();
  }

  Future<void> _initializeSync() async {
    // Initialize store
    final store = HiveSyncStore();
    await store.initialize();

    // Create adapter (example: REST)
    final adapter = RestSyncAdapter(
      config: RestSyncConfig(
        endpoint: 'https://api.example.com/sync',
      ),
    );

    // Create manager
    syncManager = OfflineSyncManager(
      store: store,
      adapter: adapter,
      config: SyncConfig(
        conflictStrategy: ConflictStrategy.lastWriteWins,
      ),
    );

    // Enable auto-sync
    final connectivityService = DefaultConnectivityService();
    syncManager.enableAutoSync();
  }

  Future<void> _saveNote() async {
    await syncManager.enqueue(
      entityType: 'note',
      entityId: 'note-1',
      operation: SyncOperation.upsert,
      payload: {
        'title': 'My Note',
        'content': 'Note content',
        'updatedAt': DateTime.now().toIso8601String(),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text('Sync Example')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: _saveNote,
                child: Text('Save Note'),
              ),
              SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => syncManager.sync(),
                child: Text('Sync Now'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

---

## New in 0.2

### Queue compaction

Consecutive changes to the same entity are merged before they hit the network:

| Queued | Then | Result |
|---|---|---|
| create | update / upsert | one **create** with the merged payload |
| update | update | one **update** with the merged payload |
| update / upsert | delete | one **delete** |
| create (never sent) | delete | **nothing is sent** |

Tasks already in flight are never merged into. Turn it off with `SyncConfig(coalesceOperations: false)`.

### Priorities and dependencies

```dart
await syncManager.enqueue(
  entityType: 'payment',
  entityId: 'pay-1',
  operation: SyncOperation.create,
  payload: payment.toJson(),
  priority: SyncPriority.critical,          // jumps the queue
);

await syncManager.enqueue(
  entityType: 'comment',
  entityId: 'c-1',
  operation: SyncOperation.create,
  payload: comment.toJson(),
  dependsOn: [EntityRef('post', 'post-1')], // waits until the post is synced
);
```

### Reactive state for your UI

```dart
StreamBuilder<SyncState>(
  stream: syncManager.stateStream,
  builder: (context, snap) {
    final s = snap.data ?? SyncState.initial;
    if (s.phase == SyncPhase.offline) return const Text('Offline');
    if (s.deadLetterCount > 0) return Text('${s.deadLetterCount} changes need attention');
    return Text(s.hasUnsyncedChanges ? '${s.outstandingCount} pending' : 'All synced');
  },
);

// Per-item badge
syncManager.watchEntity('note', note.id); // Stream<EntitySyncStatus>
```

### Dead-letter queue

Tasks that run out of retries, are rejected as non-retryable (for example an
`AdapterError` with `retryable: false`, or HTTP 400/404/422 from the REST
adapter), fail conflict resolution, or outlive `taskTimeToLive` are parked
instead of being retried forever or silently dropped:

```dart
final stuck = await syncManager.getDeadLetterTasks();
await syncManager.retryDeadLetter(stuck.first.taskId); // fresh retry budget
await syncManager.discardTask(stuck.last.taskId);      // or drop it
```

### Resilience knobs

```dart
final syncManager = OfflineSyncManager(
  store: HiveSyncStore(encryptionCipher: HiveAesCipher(key)),
  adapter: adapter,
  connectivityService: DefaultConnectivityService(),
  retryPolicy: const RetryPolicy(maxRetries: 6, jitter: 0.2),
  config: const SyncConfig(
    circuitBreaker: CircuitBreakerConfig(failureThreshold: 5, cooldown: Duration(minutes: 2)),
    taskTimeToLive: Duration(days: 7),
    syncOnEnqueueDebounce: Duration(seconds: 2),
  ),
);

final report = await syncManager.sync();  // SyncReport: succeeded, failed, deadLettered, ...
syncManager.pause();                      // e.g. user toggled "sync on Wi-Fi only"
syncManager.resume();
```

### Testing

```dart
import 'package:flutter_offline_sync_manager/testing.dart';

final adapter = FakeSyncAdapter()..failNext(1, error: 'HTTP 503');
final manager = OfflineSyncManager(store: InMemorySyncStore(), adapter: adapter);
```

See the [CHANGELOG](CHANGELOG.md) for migration notes from 0.1.x.

---

## Advanced Topics

- **[Field-Level Dirty Tracking](doc/architecture.md#dirty-tracking)** — Sync only changed fields
- **[Conflict Resolution Strategies](doc/conflict_resolution.md)** — Choose the right strategy
- **[Background Sync](doc/background_sync.md)** — Best-effort background execution
- **[Debug Inspector](doc/architecture.md#debug-inspector)** — Monitor sync state (dev-only)
- **[Custom Adapters](doc/architecture.md#custom-adapters)** — Integrate with any backend

---

## Guarantees

This package provides **explicit guarantees**:

### Data Safety
- ✅ **No data loss** — Tasks persist until server confirms receipt
- ✅ **No duplication** — Deterministic task IDs prevent duplicate syncs
- ✅ **No overwrites** — Clean fields are never overwritten during conflicts

### Reliability
- ✅ **Restart-safe** — Queue survives app kills and crashes
- ✅ **Crash-safe** — Tasks marked as syncing before network calls
- ✅ **Idempotent** — Same task can be retried safely

### Backend Support
- ✅ **Works with multiple backends** — REST, Firebase, GraphQL, or custom
- ✅ **Swappable adapters** — Easy to switch or create custom adapters
- ✅ **No schema requirements** — Works with any data structure

### OS Compliance
- ✅ **Background sync is best-effort** — Respects OS limitations
- ✅ **No foreground services** — Uses standard background APIs
- ✅ **Battery-friendly** — Respects charging and battery constraints

---

## What This Package Does NOT Do

To set proper expectations:

- ❌ **Does NOT provide UI** — You build your own UI
- ❌ **Does NOT handle authentication** — You manage auth tokens
- ❌ **Does NOT validate data** — You validate in your adapter
- ❌ **Does NOT guarantee background sync frequency** — OS-controlled
- ❌ **Does NOT provide real-time sync** — Queue-based, not event-based
- ❌ **Does NOT handle schema migrations** — You manage schema changes
- ❌ **Does NOT handle schema migrations** — You manage schema changes

---

## Documentation

- **[Architecture](doc/architecture.md)** — Deep dive into design decisions
- **[Lifecycle](doc/lifecycle.md)** — Sync lifecycle and state transitions
- **[Conflict Resolution](doc/conflict_resolution.md)** — Strategies and examples
- **[Background Sync](doc/background_sync.md)** — Platform differences and limitations
- **[FAQ](doc/faq.md)** — Common questions and answers

---

## Example App

See the [example app](example/) for a complete working implementation.

---

## Contributing

Contributions are welcome! Please read our contributing guidelines first.

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## Support

- 📖 [Documentation](doc/)
- 💬 [GitHub Discussions](https://github.com/yourusername/flutter_offline_sync_manager/discussions)
- 🐛 [Issue Tracker](https://github.com/yourusername/flutter_offline_sync_manager/issues)

---

**Built with ❤️ for the Flutter community**

