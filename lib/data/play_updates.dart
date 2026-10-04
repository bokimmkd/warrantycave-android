import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PlayUpdateState {
  const PlayUpdateState({this.version = 0, this.stage = 'idle', this.bytes = 0,
    this.total = 0, this.offer, this.installFailed = false});
  factory PlayUpdateState.fromMap(Map<dynamic, dynamic> data) => PlayUpdateState(
    version: data['version'] as int? ?? 0, stage: data['stage'] as String? ?? 'idle',
    bytes: data['bytes'] as int? ?? 0, total: data['total'] as int? ?? 0,
    offer: data['offer'] as String?, installFailed: data['installFailed'] == true);
  final int version, bytes, total;
  final String stage;
  final String? offer;
  final bool installFailed;
  double? get fraction => total > 0 ? (bytes / total).clamp(0.0, 1.0) : null;
  bool get showProgress => ['waiting', 'downloading', 'installing'].contains(stage);
}

class PlayUpdates extends ChangeNotifier {
  PlayUpdates({MethodChannel? channel}) : _channel = channel ?? const MethodChannel('com.warrantycave.app/play_updates');
  final MethodChannel _channel;
  PlayUpdateState state = const PlayUpdateState();
  bool _disposed = false;
  Future<void> initialize() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    _channel.setMethodCallHandler((call) async {
      if (!_disposed && call.method == 'changed') _accept(call.arguments);
    });
    try { _accept(await _channel.invokeMethod<Map<dynamic, dynamic>>('state')); }
    on MissingPluginException { /* Preview and non-Android hosts. */ }
    on PlatformException { /* An unavailable Play service must not block startup. */ }
  }
  void _accept(dynamic value) {
    if (_disposed || value is! Map) return;
    state = PlayUpdateState.fromMap(value); notifyListeners();
  }
  Future<void> action(String name) async {
    // Close our offer before handing control to the official Play flow.
    state = PlayUpdateState(version: state.version, stage: state.stage,
      bytes: state.bytes, total: state.total, installFailed: state.installFailed);
    notifyListeners();
    try { await _channel.invokeMethod<void>(name); }
    on PlatformException { await initialize(); }
    on MissingPluginException { /* Preview host. */ }
  }
  @override
  void dispose() { _disposed = true; _channel.setMethodCallHandler(null); super.dispose(); }
}
