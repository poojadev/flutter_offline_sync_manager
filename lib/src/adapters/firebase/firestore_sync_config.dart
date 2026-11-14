/// Configuration for Firestore sync adapter.
///
/// Example usage:
/// ```dart
/// final config = FirestoreSyncConfig(
///   collectionPath: 'sync_tasks',
///   versionField: 'version',
/// );
/// ```
class FirestoreSyncConfig {
  /// Path to the Firestore collection where entities are stored.
  ///
  /// Example: 'users', 'journal_entries', etc.
  final String collectionPath;

  /// Field name used for version/conflict detection.
  ///
  /// Default: 'version'
  /// The adapter will check this field to detect conflicts.
  final String versionField;

  /// Field name for updated timestamp.
  ///
  /// Default: 'updatedAt'
  final String updatedAtField;

  /// Whether to use Firestore transactions for batch operations.
  ///
  /// Default: true (recommended for consistency)
  final bool useTransactions;

  /// Maximum batch size for Firestore writes.
  ///
  /// Firestore has a limit of 500 operations per batch.
  /// Default: 100 (conservative)
  final int maxBatchSize;

  /// Creates a [FirestoreSyncConfig] with the given parameters.
  const FirestoreSyncConfig({
    required this.collectionPath,
    this.versionField = 'version',
    this.updatedAtField = 'updatedAt',
    this.useTransactions = true,
    this.maxBatchSize = 100,
  });

  /// Creates a [FirestoreSyncConfig] with default values.
  factory FirestoreSyncConfig.defaults(String collectionPath) {
    return FirestoreSyncConfig(collectionPath: collectionPath);
  }
}
