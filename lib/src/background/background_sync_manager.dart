import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../store/sync_store.dart';
import '../adapter/sync_adapter.dart';
import '../core/sync_config.dart';
import '../network/connectivity_service.dart';
import '../retry/retry_policy.dart';
import '../conflict/conflict_detector.dart';
import 'background_sync_config.dart';
import 'background_sync_controller.dart';
import 'background_sync_service.dart';
import 'android/android_background_sync.dart';
import 'ios/ios_background_sync.dart';

/// Manages background sync registration and execution.
///
/// This class bridges the gap between OfflineSyncManager and
/// platform-specific background sync implementations.
///
/// It handles:
/// - Platform detection (Android vs iOS)
/// - Background sync registration/unregistration
/// - Providing sync callback to platform implementations
///
/// NOTE: The app must provide factories for creating adapter and store
/// instances in the background isolate, as these cannot be passed directly
/// across isolate boundaries.
class BackgroundSyncManager {
  final Future<SyncAdapter> Function() _adapterFactory;
  final Future<SyncStore> Function()? _storeFactory;
  final SyncConfig? _config;
  final Future<ConnectivityService?> Function()? _connectivityServiceFactory;
  final RetryPolicy? _retryPolicy;
  final ConflictDetector? _conflictDetector;
  final BackgroundSyncConfig _backgroundConfig;
  BackgroundSyncController? _controller;
  bool _isRegistered = false;

  /// Creates a [BackgroundSyncManager].
  ///
  /// [adapterFactory] - Factory function that creates SyncAdapter in background isolate
  /// [storeFactory] - Optional factory function that creates SyncStore (defaults to HiveSyncStore)
  /// [backgroundConfig] - Background sync configuration
  /// [config] - Optional sync configuration
  /// [connectivityServiceFactory] - Optional factory for ConnectivityService
  /// [retryPolicy] - Optional retry policy
  /// [conflictDetector] - Optional conflict detector
  BackgroundSyncManager({
    required Future<SyncAdapter> Function() adapterFactory,
    Future<SyncStore> Function()? storeFactory,
    required BackgroundSyncConfig backgroundConfig,
    SyncConfig? config,
    Future<ConnectivityService?> Function()? connectivityServiceFactory,
    RetryPolicy? retryPolicy,
    ConflictDetector? conflictDetector,
  })  : _adapterFactory = adapterFactory,
        _storeFactory = storeFactory,
        _backgroundConfig = backgroundConfig,
        _config = config,
        _connectivityServiceFactory = connectivityServiceFactory,
        _retryPolicy = retryPolicy,
        _conflictDetector = conflictDetector {
    _controller = _createController();
  }

  /// Creates the appropriate platform-specific controller.
  BackgroundSyncController? _createController() {
    if (!_backgroundConfig.enabled) {
      return null;
    }

    // Create sync callback that executes sync in background
    final syncCallback = () async {
      // Get Hive path for background isolate
      String? hivePath;
      try {
        final dir = await getApplicationDocumentsDirectory();
        hivePath = dir.path;
      } catch (e) {
        // Fallback to default if path cannot be determined
        hivePath = null;
      }

      return await BackgroundSyncService.executeBackgroundSync(
        adapterFactory: _adapterFactory,
        storeFactory: _storeFactory,
        config: _config,
        connectivityServiceFactory: _connectivityServiceFactory,
        retryPolicy: _retryPolicy,
        conflictDetector: _conflictDetector,
        hivePath: hivePath,
      );
    };

    // Create platform-specific controller
    if (Platform.isAndroid) {
      return AndroidBackgroundSyncController(
        config: _backgroundConfig,
        syncCallback: syncCallback,
      );
    } else if (Platform.isIOS) {
      return IOSBackgroundSyncController(
        config: _backgroundConfig,
        syncCallback: syncCallback,
      );
    }

    // Unsupported platform
    return null;
  }

  /// Enables and registers background sync.
  Future<void> enable() async {
    if (_isRegistered) {
      return;
    }

    if (_controller == null) {
      _controller = _createController();
    }

    if (_controller != null) {
      await _controller!.register();
      _isRegistered = true;
    }
  }

  /// Disables and unregisters background sync.
  Future<void> disable() async {
    if (!_isRegistered) {
      return;
    }

    if (_controller != null) {
      await _controller!.unregister();
      _isRegistered = false;
    }
  }

  /// Checks if background sync is currently registered.
  Future<bool> isEnabled() async {
    if (_controller == null) {
      return false;
    }
    return await _controller!.isRegistered();
  }
}
