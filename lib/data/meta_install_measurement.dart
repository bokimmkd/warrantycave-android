import 'package:flutter/services.dart';

/// Consent is per installation, never part of the account or cloud backup.
abstract final class MetaInstallMeasurement {
  static const _channel = MethodChannel('com.warrantycave.app/meta_app_events');

  static Future<bool> enabled() async {
    try {
      return await _channel.invokeMethod<bool>('getConsent') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> setEnabled(bool enabled) =>
      _channel.invokeMethod<void>('setConsent', {'enabled': enabled});
}
