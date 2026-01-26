/// Flutter Offline Sync Manager
///
/// A production-grade package for managing offline sync operations
/// with crash-safety, restart-safety, and duplication-safety.
library flutter_offline_sync_manager;

// Core models and enums
export 'src/core/sync_task.dart';
export 'src/core/sync_operation.dart';
export 'src/core/sync_status.dart';
export 'src/core/sync_result.dart';
export 'src/core/sync_config.dart';

// Manager
export 'src/manager/offline_sync_manager.dart';

// Store abstraction
export 'src/store/sync_store.dart';
export 'src/store/hive_sync_store.dart';

// Adapter abstraction
export 'src/adapter/sync_adapter.dart';

// Network connectivity (Step 2)
export 'src/network/connectivity_service.dart';

// Retry policy (Step 2)
export 'src/retry/retry_policy.dart';

// App lifecycle (Step 2)
export 'src/lifecycle/app_lifecycle_observer.dart';

// Conflict detection and resolution (Step 3)
export 'src/conflict/conflict_strategy.dart';
export 'src/conflict/conflict_detector.dart';
export 'src/conflict/conflict_resolution.dart';
export 'src/conflict/resolution_result.dart';
export 'src/conflict/resolvers.dart';

// Background sync (Step 4)
export 'src/background/background_sync_config.dart';
export 'src/background/background_sync_controller.dart';
export 'src/background/background_sync_service.dart';
export 'src/background/background_sync_manager.dart';

// Field-level dirty tracking (Step 5)
export 'src/dirty_tracking/dirty_field.dart';
export 'src/dirty_tracking/dirty_state.dart';
export 'src/dirty_tracking/dirty_tracker.dart';
export 'src/dirty_tracking/dirty_payload_builder.dart';

// Debug inspector and observability (Step 6)
export 'src/debug/sync_event_type.dart';
export 'src/debug/sync_event.dart';
export 'src/debug/sync_metrics.dart';
export 'src/debug/sync_debug_snapshot.dart';
export 'src/debug/sync_debug_controller.dart';

// Official backend adapters (Step 7)
export 'src/adapters/adapter_errors.dart';
export 'src/adapters/rest/rest_sync_adapter.dart';
export 'src/adapters/rest/rest_sync_config.dart';
export 'src/adapters/firebase/firestore_sync_adapter.dart';
export 'src/adapters/firebase/firestore_sync_config.dart';
export 'src/adapters/graphql/graphql_sync_adapter.dart';
export 'src/adapters/graphql/graphql_sync_config.dart';

