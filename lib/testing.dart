/// Test utilities for flutter_offline_sync_manager.
///
/// ```dart
/// import 'package:flutter_offline_sync_manager/testing.dart';
/// ```
///
/// Provides an in-memory store plus scriptable fakes for the adapter and
/// connectivity, so sync flows can be tested without Hive, a network or a
/// device.
library flutter_offline_sync_manager_testing;

export 'src/store/in_memory_sync_store.dart';
export 'src/testing/fake_sync_adapter.dart';
export 'src/testing/fake_connectivity_service.dart';
