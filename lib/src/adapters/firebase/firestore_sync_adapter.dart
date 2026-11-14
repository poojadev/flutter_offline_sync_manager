import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/sync_task.dart';
import '../../core/sync_result.dart';
import '../../core/sync_operation.dart';
import 'firestore_sync_config.dart';
import '../../adapter/sync_adapter.dart';

/// Firestore sync adapter implementation.
///
/// Syncs tasks to Firestore using document-based storage.
///
/// Server Contract:
/// - Each entity is stored as a document in the configured collection
/// - Document ID: entityId
/// - Document contains:
///   - All payload fields
///   - version: number (for conflict detection)
///   - updatedAt: Timestamp
/// - Operations:
///   - create/upsert: Set document with version = 1
///   - update: Update document, increment version
///   - delete: Delete document
/// - Conflict detection: Version mismatch triggers conflict
///
/// IMPORTANT:
/// - Firestore SDK handles offline writes automatically
/// - This adapter still integrates with OfflineSyncManager queue
/// - Firestore is a transport, not a source of truth
/// - Queue logic is NOT bypassed
///
/// Example usage:
/// ```dart
/// final adapter = FirestoreSyncAdapter(
///   firestore: FirebaseFirestore.instance,
///   config: FirestoreSyncConfig(
///     collectionPath: 'journal_entries',
///     versionField: 'version',
///   ),
/// );
/// ```
class FirestoreSyncAdapter implements SyncAdapter {
  final FirebaseFirestore _firestore;
  final FirestoreSyncConfig _config;

  /// Creates a [FirestoreSyncAdapter] with the given Firestore instance and config.
  FirestoreSyncAdapter({
    required FirebaseFirestore firestore,
    required FirestoreSyncConfig config,
  })  : _firestore = firestore,
        _config = config;

  @override
  Future<SyncResult> syncBatch(List<SyncTask> tasks) async {
    if (tasks.isEmpty) {
      return const SyncResult(
        successTaskIds: {},
        failedTaskErrors: {},
      );
    }

    // Split into batches if needed
    final batches = <List<SyncTask>>[];
    for (var i = 0; i < tasks.length; i += _config.maxBatchSize) {
      batches.add(
        tasks.sublist(
          i,
          i + _config.maxBatchSize > tasks.length
              ? tasks.length
              : i + _config.maxBatchSize,
        ),
      );
    }

    final allSuccessTaskIds = <String>{};
    final allFailedTaskErrors = <String, String>{};
    final allServerData = <String, Map<String, dynamic>>{};

    // Process each batch
    for (final batch in batches) {
      try {
        if (_config.useTransactions) {
          final result = await _syncBatchWithTransaction(batch);
          allSuccessTaskIds.addAll(result.successTaskIds);
          allFailedTaskErrors.addAll(result.failedTaskErrors);
          if (result.serverData != null) {
            allServerData.addAll(result.serverData!);
          }
        } else {
          final result = await _syncBatchWithoutTransaction(batch);
          allSuccessTaskIds.addAll(result.successTaskIds);
          allFailedTaskErrors.addAll(result.failedTaskErrors);
          if (result.serverData != null) {
            allServerData.addAll(result.serverData!);
          }
        }
      } catch (e) {
        // Batch failed - mark all tasks in batch as failed
        for (final task in batch) {
          allFailedTaskErrors[task.taskId] = 'Batch sync failed: $e';
        }
      }
    }

    return SyncResult(
      successTaskIds: allSuccessTaskIds,
      failedTaskErrors: allFailedTaskErrors,
      serverData: allServerData.isEmpty ? null : allServerData,
    );
  }

  /// Syncs a batch using Firestore transactions.
  Future<SyncResult> _syncBatchWithTransaction(List<SyncTask> tasks) async {
    return await _firestore.runTransaction((transaction) async {
      final successTaskIds = <String>{};
      final failedTaskErrors = <String, String>{};
      final serverData = <String, Map<String, dynamic>>{};

      for (final task in tasks) {
        try {
          final docRef =
              _firestore.collection(_config.collectionPath).doc(task.entityId);

          final docSnapshot = await transaction.get(docRef);

          // Check for conflicts (version mismatch)
          if (docSnapshot.exists) {
            final serverVersion =
                docSnapshot.data()?[_config.versionField] as int?;
            final localVersion = task.payload[_config.versionField] as int?;

            if (serverVersion != null &&
                localVersion != null &&
                serverVersion != localVersion) {
              // Conflict detected
              failedTaskErrors[task.taskId] =
                  'Version mismatch: server=$serverVersion, local=$localVersion';
              serverData[task.taskId] = docSnapshot.data()!;
              continue;
            }
          }

          // Perform operation
          switch (task.operation) {
            case SyncOperation.create:
              if (docSnapshot.exists) {
                failedTaskErrors[task.taskId] = 'Document already exists';
                continue;
              }
              transaction.set(docRef, _buildDocumentData(task));
              break;

            case SyncOperation.update:
              if (!docSnapshot.exists) {
                failedTaskErrors[task.taskId] = 'Document does not exist';
                continue;
              }
              transaction.update(docRef, _buildDocumentData(task));
              break;

            case SyncOperation.delete:
              if (!docSnapshot.exists) {
                failedTaskErrors[task.taskId] = 'Document does not exist';
                continue;
              }
              transaction.delete(docRef);
              break;

            case SyncOperation.upsert:
              if (docSnapshot.exists) {
                transaction.update(docRef, _buildDocumentData(task));
              } else {
                transaction.set(docRef, _buildDocumentData(task));
              }
              break;
          }

          successTaskIds.add(task.taskId);
        } catch (e) {
          failedTaskErrors[task.taskId] = 'Transaction failed: $e';
        }
      }

      return SyncResult(
        successTaskIds: successTaskIds,
        failedTaskErrors: failedTaskErrors,
        serverData: serverData.isEmpty ? null : serverData,
      );
    });
  }

  /// Syncs a batch without transactions (faster but less consistent).
  Future<SyncResult> _syncBatchWithoutTransaction(List<SyncTask> tasks) async {
    final successTaskIds = <String>{};
    final failedTaskErrors = <String, String>{};
    final serverData = <String, Map<String, dynamic>>{};

    final batch = _firestore.batch();

    for (final task in tasks) {
      try {
        final docRef =
            _firestore.collection(_config.collectionPath).doc(task.entityId);

        // Check for conflicts (read first)
        final docSnapshot = await docRef.get();
        if (docSnapshot.exists) {
          final serverVersion =
              docSnapshot.data()?[_config.versionField] as int?;
          final localVersion = task.payload[_config.versionField] as int?;

          if (serverVersion != null &&
              localVersion != null &&
              serverVersion != localVersion) {
            // Conflict detected
            failedTaskErrors[task.taskId] =
                'Version mismatch: server=$serverVersion, local=$localVersion';
            serverData[task.taskId] = docSnapshot.data()!;
            continue;
          }
        }

        // Add to batch
        switch (task.operation) {
          case SyncOperation.create:
            if (docSnapshot.exists) {
              failedTaskErrors[task.taskId] = 'Document already exists';
              continue;
            }
            batch.set(docRef, _buildDocumentData(task));
            break;

          case SyncOperation.update:
            if (!docSnapshot.exists) {
              failedTaskErrors[task.taskId] = 'Document does not exist';
              continue;
            }
            batch.update(docRef, _buildDocumentData(task));
            break;

          case SyncOperation.delete:
            if (!docSnapshot.exists) {
              failedTaskErrors[task.taskId] = 'Document does not exist';
              continue;
            }
            batch.delete(docRef);
            break;

          case SyncOperation.upsert:
            if (docSnapshot.exists) {
              batch.update(docRef, _buildDocumentData(task));
            } else {
              batch.set(docRef, _buildDocumentData(task));
            }
            break;
        }

        successTaskIds.add(task.taskId);
      } catch (e) {
        failedTaskErrors[task.taskId] = 'Batch operation failed: $e';
      }
    }

    // Commit batch
    try {
      await batch.commit();
    } catch (e) {
      // Batch commit failed - mark all pending as failed
      for (final task in tasks) {
        if (!successTaskIds.contains(task.taskId) &&
            !failedTaskErrors.containsKey(task.taskId)) {
          failedTaskErrors[task.taskId] = 'Batch commit failed: $e';
        }
      }
    }

    return SyncResult(
      successTaskIds: successTaskIds,
      failedTaskErrors: failedTaskErrors,
      serverData: serverData.isEmpty ? null : serverData,
    );
  }

  /// Builds Firestore document data from a sync task.
  Map<String, dynamic> _buildDocumentData(SyncTask task) {
    final data = Map<String, dynamic>.from(task.payload);

    // Add/update version field
    if (data.containsKey(_config.versionField)) {
      data[_config.versionField] = (data[_config.versionField] as int) + 1;
    } else {
      data[_config.versionField] = 1;
    }

    // Add/update updatedAt field
    data[_config.updatedAtField] = Timestamp.fromDate(task.updatedAt);

    return data;
  }
}
