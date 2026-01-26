import 'package:flutter/material.dart';
import 'package:flutter_offline_sync_manager/flutter_offline_sync_manager.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Minimal example demonstrating offline sync.
///
/// This example shows:
/// - Initializing the sync manager
/// - Enqueueing tasks offline
/// - Manual sync trigger
/// - Basic error handling
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Hive (required for persistent storage)
  await Hive.initFlutter();
  
  runApp(const SyncExampleApp());
}

class SyncExampleApp extends StatelessWidget {
  const SyncExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Offline Sync Example',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const SyncExampleScreen(),
    );
  }
}

class SyncExampleScreen extends StatefulWidget {
  const SyncExampleScreen({super.key});

  @override
  State<SyncExampleScreen> createState() => _SyncExampleScreenState();
}

class _SyncExampleScreenState extends State<SyncExampleScreen> {
  OfflineSyncManager? _syncManager;
  bool _isInitialized = false;
  String _status = 'Initializing...';

  @override
  void initState() {
    super.initState();
    _initializeSync();
  }

  Future<void> _initializeSync() async {
    try {
      // 1. Initialize store
      final store = HiveSyncStore();
      await store.initialize();

      // 2. Create a mock adapter (for demo purposes)
      // In production, use RestSyncAdapter, FirestoreSyncAdapter, etc.
      final adapter = MockSyncAdapter();

      // 3. Create sync manager
      _syncManager = OfflineSyncManager(
        store: store,
        adapter: adapter,
        config: SyncConfig(
          batchSize: 10,
          maxRetries: 3,
          conflictStrategy: ConflictStrategy.lastWriteWins,
        ),
      );

      setState(() {
        _isInitialized = true;
        _status = 'Ready';
      });
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
      });
    }
  }

  Future<void> _createNote() async {
    if (_syncManager == null) return;

    setState(() => _status = 'Creating note...');

    try {
      // Enqueue a note for sync
      await _syncManager!.enqueue(
        entityType: 'note',
        entityId: 'note-${DateTime.now().millisecondsSinceEpoch}',
        operation: SyncOperation.upsert,
        payload: {
          'title': 'My Note',
          'content': 'This note was created offline and will sync when online.',
          'createdAt': DateTime.now().toIso8601String(),
          'updatedAt': DateTime.now().toIso8601String(),
        },
      );

      setState(() => _status = 'Note enqueued! Tap "Sync Now" to sync.');
    } catch (e) {
      setState(() => _status = 'Error: $e');
    }
  }

  Future<void> _syncNow() async {
    if (_syncManager == null) return;

    setState(() => _status = 'Syncing...');

    try {
      await _syncManager!.sync();
      setState(() => _status = 'Sync completed!');
    } catch (e) {
      setState(() => _status = 'Sync error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline Sync Example'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Status',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _status,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _isInitialized ? _createNote : null,
              icon: const Icon(Icons.add),
              label: const Text('Create Note (Offline)'),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isInitialized ? _syncNow : null,
              icon: const Icon(Icons.sync),
              label: const Text('Sync Now'),
            ),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            Text(
              'How it works:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              '1. Tap "Create Note" to enqueue a task\n'
              '2. The task is stored locally (works offline)\n'
              '3. Tap "Sync Now" to sync to server\n'
              '4. Tasks persist even if app is killed',
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _syncManager?.dispose();
    super.dispose();
  }
}

/// Mock adapter for demonstration purposes.
///
/// In production, use:
/// - RestSyncAdapter for REST APIs
/// - FirestoreSyncAdapter for Firebase
/// - GraphQLSyncAdapter for GraphQL
/// - Or implement your own SyncAdapter
class MockSyncAdapter implements SyncAdapter {
  @override
  Future<SyncResult> syncBatch(List<SyncTask> tasks) async {
    // Simulate network delay
    await Future.delayed(const Duration(seconds: 1));

    // Mock: All tasks succeed
    final successTaskIds = tasks.map((t) => t.taskId).toList();
    return SyncResult.allSuccess(successTaskIds);
  }
}

