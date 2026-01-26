/// Represents the type of sync operation to be performed.
enum SyncOperation {
  /// Create a new entity on the server.
  create,

  /// Update an existing entity on the server.
  update,

  /// Delete an entity from the server.
  delete,

  /// Upsert (create if not exists, update if exists) an entity on the server.
  /// This is the preferred operation as it handles both cases.
  upsert,
}

