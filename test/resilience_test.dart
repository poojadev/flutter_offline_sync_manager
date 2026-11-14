import 'dart:math';
import 'package:flutter_offline_sync_manager/flutter_offline_sync_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RetryPolicy', () {
    test('backoffFor grows exponentially and is capped', () {
      const policy = RetryPolicy(
          baseDelay: Duration(seconds: 1), maxDelay: Duration(seconds: 5));
      expect(policy.backoffFor(1), const Duration(seconds: 1));
      expect(policy.backoffFor(2), const Duration(seconds: 2));
      expect(policy.backoffFor(3), const Duration(seconds: 4));
      expect(policy.backoffFor(4), const Duration(seconds: 5));
      expect(policy.backoffFor(1000), const Duration(seconds: 5));
    });

    test('jitter stays within bounds', () {
      final policy = RetryPolicy(
          baseDelay: const Duration(seconds: 10),
          jitter: 0.2,
          random: Random(42));
      for (var i = 0; i < 100; i++) {
        final d = policy.backoffFor(1).inMilliseconds;
        expect(d, inInclusiveRange(8000, 12000));
      }
    });

    test('nextDelay keeps its original contract', () {
      const policy = RetryPolicy(maxRetries: 2);
      expect(policy.nextDelay(0), const Duration(seconds: 2));
      expect(policy.nextDelay(2), isNull);
    });
  });

  group('CircuitBreaker', () {
    late DateTime now;
    late CircuitBreaker breaker;

    setUp(() {
      now = DateTime(2026, 1, 1);
      breaker = CircuitBreaker(
        const CircuitBreakerConfig(
            failureThreshold: 2, cooldown: Duration(minutes: 1)),
        clock: () => now,
      );
    });

    test('opens after the threshold and half-opens after cooldown', () {
      expect(breaker.recordFailure(), isFalse);
      expect(breaker.state, CircuitState.closed);
      expect(breaker.recordFailure(), isTrue);
      expect(breaker.state, CircuitState.open);
      expect(breaker.allowsRequest, isFalse);

      now = now.add(const Duration(minutes: 1));
      expect(breaker.state, CircuitState.halfOpen);
      expect(breaker.allowsRequest, isTrue);
    });

    test('a failed trial reopens immediately', () {
      breaker
        ..recordFailure()
        ..recordFailure();
      now = now.add(const Duration(minutes: 2));
      expect(breaker.recordFailure(), isTrue);
      expect(breaker.state, CircuitState.open);
    });

    test('success closes the circuit', () {
      breaker
        ..recordFailure()
        ..recordFailure();
      expect(breaker.recordSuccess(), isTrue);
      expect(breaker.state, CircuitState.closed);
      expect(breaker.consecutiveFailures, 0);
    });
  });
}
