import 'dart:async';
import '../network/connectivity_service.dart';

/// Controllable [ConnectivityService] for tests and demos.
class FakeConnectivityService implements ConnectivityService {
  final StreamController<bool> _controller = StreamController<bool>.broadcast();
  bool _online;

  /// Creates a [FakeConnectivityService], online by default.
  FakeConnectivityService({bool online = true}) : _online = online;

  /// Current simulated status.
  bool get online => _online;

  /// Changes the simulated status and notifies listeners if it changed.
  set online(bool value) {
    if (value == _online) return;
    _online = value;
    if (!_controller.isClosed) _controller.add(value);
  }

  @override
  Stream<bool> get onStatusChange => _controller.stream;

  @override
  Future<bool> isOnline() async => _online;

  @override
  void dispose() => _controller.close();
}
