/// Configuration for [CircuitBreaker].
class CircuitBreakerConfig {
  /// Consecutive failed batches before the circuit opens.
  final int failureThreshold;

  /// How long the circuit stays open before a trial sync is allowed.
  final Duration cooldown;

  /// Creates a [CircuitBreakerConfig].
  const CircuitBreakerConfig({
    this.failureThreshold = 5,
    this.cooldown = const Duration(minutes: 1),
  }) : assert(failureThreshold > 0);
}

/// State of a [CircuitBreaker].
enum CircuitState {
  /// Requests flow normally.
  closed,

  /// Requests are blocked until the cooldown ends.
  open,

  /// The cooldown has ended; one trial request is allowed.
  halfOpen,
}

/// Stops sync attempts after repeated failures so a struggling backend is
/// not hammered by every device at once.
///
/// After [CircuitBreakerConfig.failureThreshold] consecutive failed batches
/// the circuit opens. Once [CircuitBreakerConfig.cooldown] has passed it goes
/// half-open: the next batch is a trial. Success closes the circuit; failure
/// opens it again for another cooldown.
class CircuitBreaker {
  /// Configuration.
  final CircuitBreakerConfig config;

  final DateTime Function() _clock;
  int _consecutiveFailures = 0;
  DateTime? _openedAt;

  /// Creates a [CircuitBreaker].
  CircuitBreaker(this.config, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  /// Current state.
  CircuitState get state {
    final openedAt = _openedAt;
    if (openedAt == null) return CircuitState.closed;
    return _clock().isBefore(openedAt.add(config.cooldown))
        ? CircuitState.open
        : CircuitState.halfOpen;
  }

  /// When the circuit will allow a trial request, or null if closed.
  DateTime? get openUntil => _openedAt?.add(config.cooldown);

  /// Consecutive failures recorded so far.
  int get consecutiveFailures => _consecutiveFailures;

  /// Whether a request may proceed now.
  bool get allowsRequest => state != CircuitState.open;

  /// Records a successful batch. Returns true if this closed the circuit.
  bool recordSuccess() {
    final wasOpen = _openedAt != null;
    _consecutiveFailures = 0;
    _openedAt = null;
    return wasOpen;
  }

  /// Records a failed batch. Returns true if this opened the circuit.
  bool recordFailure() {
    _consecutiveFailures++;
    final trialFailed = state == CircuitState.halfOpen;
    if (trialFailed || _consecutiveFailures >= config.failureThreshold) {
      _openedAt = _clock();
      return true;
    }
    return false;
  }

  /// Resets the breaker to closed.
  void reset() {
    _consecutiveFailures = 0;
    _openedAt = null;
  }
}
