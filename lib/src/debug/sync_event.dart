import 'sync_event_type.dart';

/// Immutable event model representing a sync lifecycle event.
///
/// Events are diagnostic only and never contain sensitive data like
/// full payloads, PII, or secrets. They are safe for logging and debugging.
class SyncEvent {
  /// Type of event that occurred.
  final SyncEventType type;

  /// Timestamp when the event occurred.
  final DateTime timestamp;

  /// Task ID associated with this event, if applicable.
  final String? taskId;

  /// Entity type associated with this event, if applicable.
  final String? entityType;

  /// Human-readable message describing the event.
  ///
  /// This is safe for logging and does not contain sensitive data.
  final String? message;

  /// Additional metadata about the event.
  ///
  /// This map never contains payload data, PII, or secrets.
  /// It may contain safe diagnostic information like:
  /// - retryCount
  /// - error codes (not full error messages with sensitive data)
  /// - field counts
  /// - status information
  final Map<String, Object?>? metadata;

  /// Creates a [SyncEvent] with the given parameters.
  const SyncEvent({
    required this.type,
    required this.timestamp,
    this.taskId,
    this.entityType,
    this.message,
    this.metadata,
  });

  /// Creates a [SyncEvent] with the current timestamp.
  factory SyncEvent.now({
    required SyncEventType type,
    String? taskId,
    String? entityType,
    String? message,
    Map<String, Object?>? metadata,
  }) {
    return SyncEvent(
      type: type,
      timestamp: DateTime.now(),
      taskId: taskId,
      entityType: entityType,
      message: message,
      metadata: metadata,
    );
  }

  @override
  String toString() {
    final buffer = StringBuffer('SyncEvent(');
    buffer.write('type: ${type.name}, ');
    buffer.write('timestamp: $timestamp');
    if (taskId != null) buffer.write(', taskId: $taskId');
    if (entityType != null) buffer.write(', entityType: $entityType');
    if (message != null) buffer.write(', message: $message');
    if (metadata != null && metadata!.isNotEmpty) {
      buffer.write(', metadata: $metadata');
    }
    buffer.write(')');
    return buffer.toString();
  }
}
