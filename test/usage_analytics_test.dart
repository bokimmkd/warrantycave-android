import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warranty_cave/data/usage_analytics.dart';
import 'package:warranty_cave/data/play_review.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const analyticsChannel = MethodChannel('test/analytics');
  const reviewChannel = MethodChannel('test/review');
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(analyticsChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(reviewChannel, null);
  });
  test('default off, no replay, minimal events only after opt-in; revoke stops immediately', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(analyticsChannel, (call) async {
          calls.add(call);
          return null;
        });
    final analytics = UsageAnalytics(channel: analyticsChannel);
    await analytics.initialize();
    expect(analytics.enabled, false);
    expect(analytics.hasChoice, false);
    await analytics.signUp('password');
    await analytics.warrantyCreated();
    expect(calls.where((c) => c.method == 'event'), isEmpty);
    await analytics.setEnabled(true);
    expect(calls.where((c) => c.method == 'event'), isEmpty);
    await analytics.signUp('google');
    await analytics.warrantyCreated();
    expect(calls.where((c) => c.method == 'event').map((c) => c.arguments), [
      {'name': 'sign_up', 'method': 'google'},
      {'name': 'warranty_created'},
    ]);
    await analytics.setEnabled(false);
    await analytics.warrantyCreated();
    expect(calls.where((c) => c.method == 'event').length, 2);
    analytics.dispose();
  });
  test('failed revocation fails closed locally; analytics failure never breaks app action', () async {
    var fail = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(analyticsChannel, (call) async {
          calls.add(call);
          if (fail) throw PlatformException(code: 'offline');
          return true;
        });
    final analytics = UsageAnalytics(channel: analyticsChannel);
    await analytics.initialize();
    expect(analytics.enabled, true);
    fail = true;
    await analytics.warrantyCreated();
    await expectLater(
      analytics.setEnabled(false),
      throwsA(isA<PlatformException>()),
    );
    expect(analytics.enabled, false);
    final count = calls.length;
    await analytics.signUp('password');
    expect(calls.length, count);
    analytics.dispose();
  });
  test('review rechecks safe route after async preparation and never launches over an editor', () async {
    var safe = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(reviewChannel, (call) async {
          calls.add(call);
          if (call.method == 'prepare') {
            safe = false;
            return true;
          }
          return null;
        });
    final reviews = PlayReview(channel: reviewChannel);
    await reviews.request(2, () => safe);
    expect(calls.map((c) => c.method), ['prepare']);
    safe = true;
    await reviews.request(2, () => safe);
    expect(calls.length, 1); // no second attempt this session
  });
  test(
    'one prepared review per session, no automatic Store fallback',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(reviewChannel, (call) async {
            calls.add(call);
            return true;
          });
      final reviews = PlayReview(channel: reviewChannel);
      await Future.wait([
        reviews.request(2, () => true),
        reviews.request(2, () => true),
      ]);
      await reviews.request(2, () => true);
      expect(calls.map((c) => c.method), ['prepare', 'launch']);
    },
  );
}
