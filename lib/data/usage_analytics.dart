import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// No replay queue, identifiers, content parameters or manually duplicated
/// first_open/session_start. Native Firebase owns those automatic events.
class UsageAnalytics extends ChangeNotifier {
  UsageAnalytics({MethodChannel? channel})
    : _channel =
          channel ??
          const MethodChannel('com.warrantycave.app/usage_analytics');
  final MethodChannel _channel;
  bool enabled = false;
  bool busy = false;
  bool hasChoice = true; // Unavailable hosts never display a consent prompt.
  bool _disposed = false;
  Future<void> initialize() async {
    try {
      final choice = await _channel.invokeMethod<bool>('choice');
      enabled = choice == true;
      hasChoice = choice != null;
    } catch (_) {
      enabled = false;
      hasChoice = true;
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    if (busy) return;
    busy = true;
    // Stop Dart events immediately even if persistence/native code fails.
    enabled = false;
    if (!_disposed) notifyListeners();
    try {
      await _channel.invokeMethod<void>('setConsent', {'enabled': value});
      enabled = value;
      hasChoice = true;
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> signUp(String method) => _event('sign_up', method: method);
  Future<void> warrantyCreated() => _event('warranty_created');
  Future<void> _event(String name, {String? method}) async {
    if (!enabled || _disposed) return;
    try {
      await _channel.invokeMethod<void>('event', {
        'name': name,
        if (method != null) 'method': method,
      });
    } catch (_) {
      /* Measurement must never break a successful app action. */
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
