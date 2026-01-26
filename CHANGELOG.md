# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1] - 2026-01-26

### Fixed
- Dependency resolution issues when consuming apps use newer backend SDK versions
- Relaxed backend adapter dependency constraints:
    - `cloud_firestore: >=4.0.0 <6.0.0` (supports both 4.x and 5.x)
    - `http: >=0.13.0 <2.0.0` (supports both 0.13.x and 1.x)
- Fixed compilation errors caused by strict dependency pinning
- No API changes

## [0.1.0] - 2026-01-26

### Added
- Offline-first sync engine with crash-safe and restart-safe guarantees
- Persistent sync queue using Hive
- Deterministic task IDs to prevent duplication
- Connectivity-aware automatic syncing
- Exponential backoff retry strategy
- Conflict detection and resolution strategies
- Field-level dirty tracking
- Background sync support (Android WorkManager, iOS Background Fetch)
- REST, Firestore, and GraphQL backend adapters
- Debug inspector and sync metrics
- Comprehensive documentation and example app
