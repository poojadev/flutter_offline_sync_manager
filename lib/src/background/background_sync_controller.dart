/// Abstract interface for platform-specific background sync controllers.
///
/// Handles registration and unregistration of background sync tasks
/// on different platforms (Android, iOS).
///
/// This controller does NOT perform sync itself - it only manages
/// the platform-specific background task registration.
abstract class BackgroundSyncController {
  /// Registers background sync tasks with the platform.
  ///
  /// This should be called when background sync is enabled.
  /// Must be idempotent and safe to call multiple times.
  Future<void> register();

  /// Unregisters background sync tasks from the platform.
  ///
  /// This should be called when background sync is disabled or
  /// when the app is being disposed.
  /// Must be idempotent and safe to call multiple times.
  Future<void> unregister();

  /// Checks if background sync is currently registered.
  Future<bool> isRegistered();
}

