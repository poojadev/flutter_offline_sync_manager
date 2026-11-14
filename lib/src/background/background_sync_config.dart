/// Configuration for background sync operations.
///
/// Provides conservative, OS-safe defaults that respect platform limitations.
class BackgroundSyncConfig {
  /// Whether background sync is enabled.
  final bool enabled;

  /// Minimum interval between background sync attempts.
  ///
  /// Android requires minimum 15 minutes for periodic work.
  /// iOS background fetch is best-effort and OS-controlled.
  final Duration minInterval;

  /// Whether network connectivity is required for background sync.
  final bool requiresNetwork;

  /// Whether device must be charging (Android only).
  final bool requiresCharging;

  /// Whether background sync is allowed when battery is low.
  final bool allowLowBattery;

  /// Creates a [BackgroundSyncConfig] with the given parameters.
  const BackgroundSyncConfig({
    this.enabled = false,
    this.minInterval = const Duration(minutes: 15),
    this.requiresNetwork = true,
    this.requiresCharging = false,
    this.allowLowBattery = true,
  });

  /// Creates a [BackgroundSyncConfig] with conservative, OS-safe defaults.
  factory BackgroundSyncConfig.defaults() {
    return const BackgroundSyncConfig();
  }

  /// Creates a [BackgroundSyncConfig] with background sync enabled.
  factory BackgroundSyncConfig.enabled({
    Duration? minInterval,
    bool? requiresNetwork,
    bool? requiresCharging,
    bool? allowLowBattery,
  }) {
    return BackgroundSyncConfig(
      enabled: true,
      minInterval: minInterval ?? const Duration(minutes: 15),
      requiresNetwork: requiresNetwork ?? true,
      requiresCharging: requiresCharging ?? false,
      allowLowBattery: allowLowBattery ?? true,
    );
  }
}
