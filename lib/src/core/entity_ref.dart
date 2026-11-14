/// A reference to a single entity, used to declare dependencies between
/// sync tasks.
///
/// A task that `dependsOn` an [EntityRef] is held back until that entity has
/// no unsynced tasks left in the queue. For example, a `comment` can depend
/// on the `post` it belongs to, so the comment is never sent before the post
/// exists on the server.
class EntityRef {
  /// The entity type (e.g. `'post'`).
  final String entityType;

  /// The entity identifier.
  final String entityId;

  /// Creates an [EntityRef].
  const EntityRef(this.entityType, this.entityId);

  /// Stable key for this entity, used internally for lookups.
  String get key => entityKey(entityType, entityId);

  /// Builds the stable key for an entity.
  static String entityKey(String entityType, String entityId) =>
      '$entityType\u0000$entityId';

  /// Serializes this reference to a map.
  Map<String, dynamic> toMap() => {'type': entityType, 'id': entityId};

  /// Deserializes a reference from a map produced by [toMap].
  factory EntityRef.fromMap(Map<dynamic, dynamic> map) =>
      EntityRef(map['type'] as String, map['id'] as String);

  @override
  bool operator ==(Object other) =>
      other is EntityRef &&
      other.entityType == entityType &&
      other.entityId == entityId;

  @override
  int get hashCode => Object.hash(entityType, entityId);

  @override
  String toString() => 'EntityRef($entityType, $entityId)';
}
