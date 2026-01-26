# flutter_offline_sync_manager

**Offline-first, conflict-safe, backend-agnostic sync engine for Flutter**

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
- **Persistent sync queue** using Hive (survives app restarts)
- **Deterministic task IDs** prevent duplicate syncs
- **Single-flight sync** prevents parallel execution
- **Batch sync** with partial success handling

### Automation & Reliability
- **Auto-retry** with exponential backoff
- **Connectivity awareness** (only syncs when online)
- **App lifecycle hooks** (syncs on resume)
- **Background sync** (best-effort, OS-compliant)

### Conflict Resolution
- **Multiple strategies** (last-write-wins, server-wins, client-wins, field-merge)
- **Field-level dirty tracking** (sync only changed fields)
- **Safe merging** (never overwrites clean data)
- **Custom resolvers** for complex scenarios

### Developer Experience
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
  flutter_offline_sync_manager: ^0.1.0
  hive: ^2.2.3
  hive_flutter: ^2.0.0
```

### 2. Initialize Hive

```dart
import 'package:hive_flutter/hive_flutter.dart';

void main() async {
  await Hive.initFlutter();
  runApp(MyApp());
}
```

### 3. Create Sync Adapter

```dart
import 'package:flutter_offline_sync_manager/flutter_offline_sync_manager.dart';

// Example: REST adapter
final adapter = RestSyncAdapter(
  config: RestSyncConfig(
    endpoint: 'https://api.example.com/sync',
    headersProvider: () => {'Authorization': 'Bearer $token'},
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

### Backend Agnostic
- ✅ **Works with any backend** — REST, Firebase, GraphQL, or custom
- ✅ **No backend assumptions** — Adapters are swappable
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

