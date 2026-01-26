# Example App

This example demonstrates basic usage of `flutter_offline_sync_manager`.

## Running the Example

1. Install dependencies:
```bash
cd example
flutter pub get
```

2. Run the app:
```bash
flutter run
```

## What It Demonstrates

- Initializing Hive for persistent storage
- Creating a sync manager with a mock adapter
- Enqueueing tasks offline
- Manual sync trigger
- Basic error handling

## Next Steps

- Replace `MockSyncAdapter` with `RestSyncAdapter`, `FirestoreSyncAdapter`, or your own adapter
- Add connectivity service for auto-sync
- Enable background sync
- Add field-level dirty tracking
- Configure conflict resolution strategy

See the main [README.md](../README.md) for more examples.

