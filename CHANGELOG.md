# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2024-01-XX

### Added

#### Core Engine (Step 1)
- Persistent sync queue using Hive
- Deterministic task IDs prevent duplicates
- Single-flight sync prevents parallel execution
- Batch sync with partial success handling
- Crash-safe state management
- Restart-safe queue persistence

#### Automation & Retries (Step 2)
- Connectivity awareness (only syncs when online)
- Auto-sync on network reconnect
- Auto-sync on app resume
- Exponential backoff retry policy
- Configurable retry limits

#### Conflict Resolution (Step 3)
- Conflict detection (version mismatch, server flags, error codes)
- Multiple resolution strategies:
  - Last write wins (default)
  - Server wins
  - Client wins
  - Field-level merge
  - Custom resolvers
- Safe conflict handling (no data loss)

#### Background Sync (Step 4)
- Android background sync via WorkManager
- iOS background sync via background fetch
- Best-effort, OS-compliant execution
- Configurable constraints (network, charging, battery)

#### Field-Level Dirty Tracking (Step 5)
- Track which fields changed
- Sync only dirty fields (partial payloads)
- Field-level conflict resolution
- Preserve clean fields during merge

#### Debug Inspector (Step 6)
- Sync event stream (dev-only)
- Metrics aggregation (counters, timers)
- Read-only state snapshots
- Zero overhead when disabled

#### Official Backend Adapters (Step 7)
- REST adapter (ready-to-use)
- Firebase Firestore adapter (ready-to-use)
- GraphQL adapter (ready-to-use)
- Typed adapter errors
- Configurable adapters

### Features

- **Data Safety**: Zero data loss, zero duplication
- **Reliability**: Crash-safe, restart-safe, idempotent
- **Backend Agnostic**: Works with any backend
- **Production Ready**: Battle-tested patterns and safeguards
- **Developer Friendly**: Debug tools, examples, documentation

### Documentation

- Comprehensive README with quick start
- Architecture documentation
- Lifecycle documentation
- Conflict resolution guide
- Background sync guide
- FAQ
- Example app

---

[0.1.0]: https://github.com/yourusername/flutter_offline_sync_manager/releases/tag/v0.1.0

