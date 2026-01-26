/// Strategy for resolving conflicts between local and server data.
///
/// Conflicts occur when both local and server data have been modified
/// independently, requiring a decision on which version to keep.
enum ConflictStrategy {
  /// Last write wins - the version with the most recent timestamp wins.
  /// This is the default strategy and works well for most use cases.
  lastWriteWins,

  /// Server always wins - local changes are discarded in favor of server data.
  /// Use this when server is the source of truth.
  serverWins,

  /// Client always wins - local changes are preserved and retried.
  /// Use this when local edits should take precedence.
  clientWins,

  /// Field-level merge - merges non-conflicting fields from both versions.
  /// Conflicting fields use client values. This is a safe, shallow merge.
  fieldLevelMerge,

  /// Custom strategy - uses a developer-provided resolver.
  /// Allows for application-specific conflict resolution logic.
  custom,
}

