# Background Sync

This document explains background sync capabilities, platform differences, and limitations.

## Overview

Background sync allows the sync engine to run when the app is not in the foreground. This is **best-effort** and **OS-controlled** - the operating system decides when and if to execute background work.

## Platform Differences

### Android

Uses **WorkManager** for background execution.

**Characteristics:**
- Minimum interval: 15 minutes (Android requirement)
- Respects battery and network constraints
- Can be delayed by Doze mode
- Works even if app is force-stopped (after restart)

**Constraints:**
- Requires network (if configured)
- Can require charging (if configured)
- Battery not low (if configured)
- Minimum 15-minute intervals

### iOS

Uses **background fetch** for background execution.

**Characteristics:**
- OS-controlled frequency (not guaranteed)
- Based on user behavior patterns
- May not execute if user doesn't use app frequently
- Time-limited execution (~30 seconds)

**Constraints:**
- Best-effort (no guarantees)
- OS decides when to run
- Limited execution time
- May not run if battery is low

## Best-Effort Guarantee

**Important:** Background sync is **best-effort**. This means:

- ✅ **May** run in the background
- ❌ **Not guaranteed** to run
- ❌ **Not guaranteed** frequency
- ❌ **Not guaranteed** execution time

**Recommendation:** Don't rely solely on background sync. Use it as a supplement to foreground sync.

## Configuration

### Basic Setup

```dart
final backgroundManager = BackgroundSyncManager(
  adapterFactory: () async => MySyncAdapter(),
  storeFactory: () async => HiveSyncStore(),
  backgroundConfig: BackgroundSyncConfig.enabled(
    minInterval: Duration(minutes: 15),
    requiresNetwork: true,
  ),
);

await backgroundManager.enable();
```

### Configuration Options

- `enabled`: Enable/disable background sync
- `minInterval`: Minimum time between syncs (15 min for Android)
- `requiresNetwork`: Only sync when online
- `requiresCharging`: Only sync when charging (Android)
- `allowLowBattery`: Allow sync when battery is low

## How It Works

### Android (WorkManager)

1. App registers periodic work with WorkManager
2. WorkManager schedules work based on constraints
3. When work executes, calls background sync service
4. Service initializes Hive in background isolate
5. Service creates sync manager and calls `sync()`
6. Results are persisted back to Hive

### iOS (Background Fetch)

1. App registers for background fetch
2. iOS decides when to trigger fetch
3. When triggered, calls background sync service
4. Service has ~30 seconds to complete
5. Service initializes and syncs
6. Service signals completion to iOS

## Limitations

### Android Limitations

- **15-minute minimum**: Cannot sync more frequently
- **Doze mode**: May delay execution
- **Battery optimization**: Users can disable
- **Force-stop**: Work stops until app is opened again

### iOS Limitations

- **No frequency guarantee**: OS decides when to run
- **Time limit**: ~30 seconds execution time
- **User behavior**: May not run if app isn't used
- **Battery**: May not run if battery is low

## Best Practices

### 1. Don't Rely on Background Sync

Use foreground sync as primary:
```dart
// Primary: Sync on app resume
syncManager.enableAutoSync();

// Supplement: Background sync
backgroundManager.enable();
```

### 2. Handle Time Limits (iOS)

Keep background work fast:
- Sync small batches
- Don't do heavy processing
- Exit quickly if time expires

### 3. Test Background Behavior

Test on real devices:
- Test with app in background
- Test with app killed
- Test with low battery
- Test with no network

### 4. Monitor Background Execution

Use debug inspector to monitor:
```dart
debugController.events.listen((event) {
  if (event.type == SyncEventType.backgroundSyncTriggered) {
    print('Background sync triggered');
  }
});
```

## Troubleshooting

### Background Sync Not Running

**Android:**
- Check battery optimization settings
- Verify WorkManager is registered
- Check network connectivity
- Wait at least 15 minutes

**iOS:**
- Background fetch may not run if app isn't used
- Check background refresh settings
- iOS learns user patterns over time

### Background Sync Too Infrequent

- This is expected (OS-controlled)
- Use foreground sync for immediate sync
- Background sync is supplement, not primary

### Background Sync Failing

- Check adapter implementation
- Verify Hive initialization in background isolate
- Check error handling in background service
- Review logs (if available)

## Alternatives

If background sync doesn't meet your needs:

1. **Foreground sync**: Sync when app is active
2. **Push notifications**: Trigger sync via push
3. **Foreground service**: Keep app active (not recommended)
4. **Periodic foreground checks**: Check on app resume

## Summary

Background sync is a **useful supplement** but not a **reliable primary** sync mechanism. Use it to:
- Catch up on missed syncs
- Reduce foreground sync load
- Improve user experience (seamless sync)

But always have foreground sync as your primary mechanism.

