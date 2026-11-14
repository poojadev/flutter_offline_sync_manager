import 'dart:async';
import 'package:background_fetch/background_fetch.dart';
import '../background_sync_controller.dart';
import '../background_sync_config.dart';
import '../background_sync_service.dart';

/// iOS implementation of background sync using background_fetch.
///
/// Uses iOS background fetch which is best-effort and OS-controlled.
/// iOS decides when to execute background fetch based on user behavior
/// and system resources.
class IOSBackgroundSyncController implements BackgroundSyncController {
  final BackgroundSyncConfig _config;
  final BackgroundSyncCallback _syncCallback;
  bool _isRegistered = false;

  /// Creates an [IOSBackgroundSyncController].
  ///
  /// [config] - Background sync configuration
  /// [syncCallback] - Callback function that executes the sync
  IOSBackgroundSyncController({
    required BackgroundSyncConfig config,
    required BackgroundSyncCallback syncCallback,
  })  : _config = config,
        _syncCallback = syncCallback;

  @override
  Future<void> register() async {
    if (!_config.enabled) {
      return;
    }

    try {
      // Initialize background fetch
      await BackgroundFetch.configure(
        BackgroundFetchConfig(
          minimumFetchInterval: _config.minInterval.inMinutes,
          stopOnTerminate: false,
          startOnBoot: true,
          enableHeadless: true,
          requiresStorageNotLow: false,
          requiresBatteryNotLow: !_config.allowLowBattery,
          requiresCharging: _config.requiresCharging,
          requiresDeviceIdle: false,
          requiredNetworkType:
              _config.requiresNetwork ? NetworkType.ANY : NetworkType.NONE,
        ),
        _onBackgroundFetch,
        _onBackgroundFetchTimeout,
      );

      _isRegistered = true;
    } catch (e) {
      // Fail silently - background sync is best-effort
      // iOS may not grant background fetch permission
      _isRegistered = false;
    }
  }

  @override
  Future<void> unregister() async {
    try {
      await BackgroundFetch.stop();
      _isRegistered = false;
    } catch (e) {
      // Fail silently
    }
  }

  @override
  Future<bool> isRegistered() async {
    return _isRegistered;
  }

  /// Callback when iOS executes background fetch.
  void _onBackgroundFetch(String taskId) async {
    try {
      // Execute sync callback
      await _syncCallback();

      // Signal completion to iOS
      BackgroundFetch.finish(taskId);
    } catch (e) {
      // Fail silently - background sync is best-effort
      BackgroundFetch.finish(taskId);
    }
  }

  /// Callback when iOS background fetch times out.
  void _onBackgroundFetchTimeout(String taskId) {
    // iOS is terminating the background task
    // Abort gracefully without doing any work
    BackgroundFetch.finish(taskId);
  }
}
