# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.2] - 2026-01-26

### Fixed
- Corrected README installation instructions
- Clarified backend dependency usage (Firestore, REST/GraphQL)
- Fixed example app dependencies
- No runtime or API changes

## [0.1.1] - 2026-01-26

### Fixed
- Relaxed dependency constraints for backend SDKs
    - `cloud_firestore: >=4.0.0 <6.0.0`
    - `http: >=0.13.0 <2.0.0`
- Fixed dependency resolution issues in consuming apps
- No API changes

## [0.1.0] - 2026-01-26

### Added
- Initial release
- Offline-first sync engine with crash-safety and restart-safety
- Background sync, retry logic, conflict resolution
- REST, Firestore, and GraphQL adapters
