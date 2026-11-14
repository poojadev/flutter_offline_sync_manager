import 'package:flutter/widgets.dart';

/// Observer for app lifecycle events.
///
/// Detects when the app resumes from background and calls a provided callback.
/// This is a lightweight observer that does not require UI code.
class AppLifecycleObserver extends WidgetsBindingObserver {
  /// Callback invoked when the app resumes from background.
  final VoidCallback onResume;

  /// Whether the observer is currently attached.
  bool _isAttached = false;

  /// Creates an [AppLifecycleObserver] with the given resume callback.
  AppLifecycleObserver({required this.onResume});

  /// Attaches this observer to the widget binding.
  ///
  /// Must be called to start receiving lifecycle events.
  void attach() {
    if (!_isAttached) {
      WidgetsBinding.instance.addObserver(this);
      _isAttached = true;
    }
  }

  /// Detaches this observer from the widget binding.
  ///
  /// Should be called when the observer is no longer needed to prevent memory leaks.
  void detach() {
    if (_isAttached) {
      WidgetsBinding.instance.removeObserver(this);
      _isAttached = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onResume();
    }
  }
}
