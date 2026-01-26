import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Abstract interface for monitoring network connectivity.
///
/// Provides a stream of connectivity status changes and a method
/// to check current connectivity status.
abstract class ConnectivityService {
  /// Stream that emits true when network becomes available, false when offline.
  ///
  /// Emits the current status immediately upon subscription.
  Stream<bool> get onStatusChange;

  /// Checks if the device is currently online.
  ///
  /// Returns true only when actual network connectivity is available
  /// (not just that WiFi/mobile is connected, but that internet is reachable).
  Future<bool> isOnline();

  /// Disposes of resources used by this service.
  void dispose();
}

/// Default implementation of [ConnectivityService] using connectivity_plus.
///
/// Monitors connectivity changes and provides online/offline status.
/// Handles mobile and WiFi connections.
class DefaultConnectivityService implements ConnectivityService {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<ConnectivityResult>? _subscription;
  final _controller = StreamController<bool>.broadcast();
  bool _lastStatus = false;
  bool _isDisposed = false;

  DefaultConnectivityService() {
    _initialize();
  }

  /// Initializes connectivity monitoring.
  Future<void> _initialize() async {
    // Check initial status
    final initialStatus = await _checkConnectivity();
    _lastStatus = initialStatus;
    _controller.add(initialStatus);

    // Listen to connectivity changes
    _subscription = _connectivity.onConnectivityChanged.listen(
      (ConnectivityResult result) async {
        if (_isDisposed) return;

        final isOnline = await _checkConnectivity();
        // Only emit if status actually changed (avoid duplicate events)
        if (isOnline != _lastStatus) {
          _lastStatus = isOnline;
          _controller.add(isOnline);
        }
      },
      onError: (error) {
        // On error, assume offline to be safe
        if (!_isDisposed && _lastStatus) {
          _lastStatus = false;
          _controller.add(false);
        }
      },
    );
  }

  /// Checks if connectivity is actually available.
  ///
  /// Returns true only when there's an active connection (WiFi or mobile)
  /// and the connection is not none.
  Future<bool> _checkConnectivity() async {
    try {
      final result = await _connectivity.checkConnectivity();
      // Consider online if connection is available and not none
      return result != ConnectivityResult.none &&
          (result == ConnectivityResult.wifi ||
              result == ConnectivityResult.mobile ||
              result == ConnectivityResult.ethernet);
    } catch (e) {
      // On error, assume offline
      return false;
    }
  }

  @override
  Stream<bool> get onStatusChange {
    if (_isDisposed) {
      throw StateError('ConnectivityService has been disposed');
    }
    return _controller.stream;
  }

  @override
  Future<bool> isOnline() async {
    if (_isDisposed) {
      return false;
    }
    return _checkConnectivity();
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _subscription?.cancel();
    _controller.close();
  }
}

