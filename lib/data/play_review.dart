import 'package:flutter/services.dart';

class PlayReview {
  PlayReview({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('com.warrantycave.app/play_review');
  final MethodChannel _channel;
  bool _inFlight = false;
  bool _attempted = false;
  Future<void> observe(int count, {bool existingAccount = false}) async {
    try {
      await _channel.invokeMethod<void>('observe', {
        'count': count,
        'existingAccount': existingAccount,
      });
    } catch (_) {
      /* Unsupported hosts do not block app startup. */
    }
  }

  Future<void> request(int count, bool Function() stillSafe) async {
    if (_inFlight || _attempted || !stillSafe()) return;
    _inFlight = true;
    try {
      final prepared =
          await _channel.invokeMethod<bool>('prepare', {'count': count}) ??
          false;
      if (prepared) {
        _attempted = true;
        if (stillSafe()) await _channel.invokeMethod<bool>('launch');
      }
    } catch (_) {
      /* No Store fallback, no claim that the user left a rating. */
    } finally {
      _inFlight = false;
    }
  }
}
