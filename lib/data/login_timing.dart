import 'package:flutter/foundation.dart';

/// Local debug diagnostics only: never identifiers, tokens or user content.
Future<T> timeLoginStage<T>(String stage, Future<T> Function() action) async {
  final watch = Stopwatch()..start();
  try {
    return await action();
  } finally {
    if (kDebugMode) debugPrint('WC login $stage: ${watch.elapsedMilliseconds}ms');
  }
}
