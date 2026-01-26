import 'dart:async';
import 'package:hive/hive.dart';
import '../store/sync_store.dart';
import '../store/hive_sync_store.dart';
import '../adapter/sync_adapter.dart';
import '../manager/offline_sync_manager.dart';
import '../core/sync_config.dart';
import '../network/connectivity_service.dart';
import '../retry/retry_policy.dart';
import '../conflict/conflict_detector.dart';

/// Service that bridges background sync execution with OfflineSyncManager.
///
/// This service is responsible for:
/// - Initializing storage in background isolate
/// - Creating OfflineSyncManager instance in background context
/// - Executing sync once per background execution
/// - Handling errors gracefully without crashing
///
/// CRITICAL: This must be idempotent, restart-safe, and must not
/// assume the UI isolate exists.
class BackgroundSyncService {
  /// Entry point for background sync execution.
  ///
  /// This method is called from platform-specific background callbacks
  /// (Android WorkManager, iOS background fetch).
  ///
  /// Parameters:
  /// - [adapterFactory] - Function that creates a SyncAdapter instance
  /// - [storeFactory] - Optional function that creates a SyncStore instance
  ///   (defaults to HiveSyncStore)
  /// - [config] - Optional sync configuration
  /// - [connectivityServiceFactory] - Optional function that creates ConnectivityService
  /// - [retryPolicy] - Optional retry policy
  /// - [conflictDetector] - Optional conflict detector
  /// - [hivePath] - Optional Hive storage path (must match main isolate path)
  ///
  /// Returns true if sync was attempted (regardless of success/failure).
  /// Returns false if sync could not be executed (e.g., initialization failed).
  static Future<bool> executeBackgroundSync({
    required Future<SyncAdapter> Function() adapterFactory,
    Future<SyncStore> Function()? storeFactory,
    SyncConfig? config,
    Future<ConnectivityService?> Function()? connectivityServiceFactory,
    RetryPolicy? retryPolicy,
    ConflictDetector? conflictDetector,
    String? hivePath,
  }) async {
    try {
      // Initialize Hive in background isolate if not already initialized
      // Hive must be initialized in the isolate where it's used
      if (!Hive.isBoxOpen('sync_tasks')) {
        if (hivePath != null) {
          Hive.init(hivePath);
        } else {
          // Try to initialize with default path
          // In Flutter, this should be the app's documents directory
          // The app should provide the correct path
          Hive.init('.');
        }
      }

      // Create store (default to HiveSyncStore if not provided)
      final store = storeFactory != null
          ? await storeFactory()
          : HiveSyncStore();
      
      // Initialize store (HiveSyncStore has initialize method)
      if (store is HiveSyncStore) {
        await store.initialize();
      }

      // Create adapter
      final adapter = await adapterFactory();

      // Create optional connectivity service
      ConnectivityService? connectivityService;
      if (connectivityServiceFactory != null) {
        connectivityService = await connectivityServiceFactory();
      }

      // Create sync manager
      final manager = OfflineSyncManager(
        store: store,
        adapter: adapter,
        config: config,
        connectivityService: connectivityService,
        retryPolicy: retryPolicy,
        conflictDetector: conflictDetector,
      );

      // Execute sync once using background sync method
      // This will respect all existing logic: single-flight, retry backoff, etc.
      final success = await manager.runBackgroundSync();

      // Cleanup
      manager.dispose();
      connectivityService?.dispose();

      return success;
    } catch (e) {
      // Fail silently - background sync is best-effort
      // Logging would be ideal but we don't want to crash
      return false;
    }
  }
}

/// Callback function type for background sync execution.
///
/// This is used by platform-specific implementations to invoke
/// background sync in a type-safe way.
typedef BackgroundSyncCallback = Future<bool> Function();

