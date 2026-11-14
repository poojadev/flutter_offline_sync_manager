import 'package:workmanager/workmanager.dart';
import '../background_sync_controller.dart';
import '../background_sync_config.dart';
import '../background_sync_service.dart';

/// Android implementation of background sync using WorkManager.
///
/// Uses PeriodicWorkRequest with minimum 15-minute interval as required by Android.
/// Respects network and charging constraints.
class AndroidBackgroundSyncController implements BackgroundSyncController {
  static const String _taskName = 'flutter_offline_sync_background_task';
  final BackgroundSyncConfig _config;
  // Note: _syncCallback is stored for potential future use
  // Currently, callbackDispatcher runs in a separate isolate
  // and cannot access this instance, so the callback must be
  // provided via a mechanism that works across isolates
  @pragma('vm:entry-point')
  @pragma('vm:keep-name')
  final BackgroundSyncCallback syncCallback;

  /// Creates an [AndroidBackgroundSyncController].
  ///
  /// [config] - Background sync configuration
  /// [syncCallback] - Callback function that executes the sync
  AndroidBackgroundSyncController({
    required BackgroundSyncConfig config,
    required BackgroundSyncCallback syncCallback,
  })  : _config = config,
        syncCallback = syncCallback;

  @override
  Future<void> register() async {
    if (!_config.enabled) {
      return;
    }

    try {
      // Initialize WorkManager
      await Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: false,
      );

      // Cancel any existing work
      await unregister();

      // Create constraints
      final constraints = Constraints(
        networkType: _config.requiresNetwork
            ? NetworkType.connected
            : NetworkType.not_required,
        requiresCharging: _config.requiresCharging,
        requiresBatteryNotLow: !_config.allowLowBattery,
      );

      // Calculate interval (must be at least 15 minutes for Android)
      final interval = _config.minInterval.inMinutes;
      final minInterval = interval < 15 ? 15 : interval;

      // Register periodic work
      await Workmanager().registerPeriodicTask(
        _taskName,
        _taskName,
        frequency: Duration(minutes: minInterval),
        constraints: constraints,
        initialDelay: Duration(minutes: minInterval),
      );
    } catch (e) {
      // Fail silently - background sync is best-effort
      // If registration fails, app should continue working normally
    }
  }

  @override
  Future<void> unregister() async {
    try {
      await Workmanager().cancelByUniqueName(_taskName);
    } catch (e) {
      // Fail silently
    }
  }

  @override
  Future<bool> isRegistered() async {
    try {
      // WorkManager doesn't provide a direct way to check if work is registered
      // We'll assume it's registered if enabled in config
      return _config.enabled;
    } catch (e) {
      return false;
    }
  }
}

/// Callback dispatcher for WorkManager.
///
/// This is the entry point called by Android WorkManager when
/// background work should be executed.
///
/// NOTE: The actual sync execution requires adapter and store factories.
/// These must be provided by the app and stored in a way accessible
/// from the background isolate (e.g., via a service locator or
/// dependency injection container that works across isolates).
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == 'flutter_offline_sync_background_task') {
      try {
        // Execute background sync
        // The actual implementation should call:
        // BackgroundSyncService.executeBackgroundSync(
        //   adapterFactory: () => createAdapter(),
        //   storeFactory: () => createStore(),
        //   ...
        // )
        //
        // Since we can't pass closures across isolates, the app must
        // provide these factories via a mechanism that works in background isolate
        // (e.g., service locator, dependency injection, or static factories)
        
        // For now, this is a placeholder that returns success
        // The actual sync execution should be implemented by the app
        // using BackgroundSyncService.executeBackgroundSync()
        return true;
      } catch (e) {
        // Fail silently - background sync is best-effort
        return false;
      }
    }
    return false;
  });
}

