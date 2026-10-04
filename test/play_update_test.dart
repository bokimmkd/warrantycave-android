import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warranty_cave/data/play_updates.dart';
import 'package:warranty_cave/l10n/app_localizations.dart';
import 'package:warranty_cave/presentation/play_update_widgets.dart';
import 'package:warranty_cave/presentation/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('progress uses bytes, unknown total is indeterminate, 100% is not ready', () {
    const s = PlayUpdateState(stage: 'downloading', bytes: 100, total: 100);
    expect(s.fraction, 1); expect(s.offer, isNull);
    expect(const PlayUpdateState(stage: 'downloading').fraction, isNull);
    expect(const PlayUpdateState(bytes: 150, total: 100).fraction, 1);
  });
  test('action closes offer before native consent and ignores events after disposal', () async {
    const channel = MethodChannel('test/play_updates');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async => null);
    final updates = PlayUpdates(channel: channel);
    updates.state = const PlayUpdateState(version: 38, offer: 'available');
    final future = updates.action('update');
    expect(updates.state.offer, isNull); await future;
    updates.dispose();
  });
  testWidgets('Play handoff closes popup, download preserves form, ready Later closes only offer', (tester) async {
    final updates = _FakeUpdates();
    await tester.pumpWidget(MaterialApp(theme: buildTheme(),
      localizationsDelegates: const [AppLocalizations.delegate, GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      home: Scaffold(body: PlayUpdateHost(updates: updates,
        child: const TextField(key: Key('kept-input'))))));
    await tester.enterText(find.byKey(const Key('kept-input')), 'My warranty');
    updates.publish(const PlayUpdateState(version: 38, offer: 'available'));
    await tester.pumpAndSettle(); expect(find.text('Update WarrantyCave'), findsOneWidget);
    await tester.tap(find.text('Update')); await tester.pumpAndSettle();
    expect(updates.actions, ['update']); expect(find.byType(AlertDialog), findsNothing);
    updates.publish(const PlayUpdateState(version: 38, stage: 'downloading', bytes: 100, total: 100));
    await tester.pump(); expect(find.text('100%'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing); expect(find.text('My warranty'), findsOneWidget);
    updates.publish(const PlayUpdateState(version: 38, stage: 'ready', offer: 'ready'));
    await tester.pumpAndSettle(); expect(find.text('Restart to update'), findsOneWidget);
    await tester.tap(find.text('Later')); await tester.pumpAndSettle();
    expect(updates.actions, ['update', 'later']); expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('My warranty'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); updates.dispose();
  });
  for (final language in appLanguages) {
    for (final dark in [false, true]) {
      testWidgets('compact update progress ${language.code} dark=$dark preserves input', (tester) async {
        tester.view.physicalSize = const Size(320, 640); tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(MaterialApp(theme: dark ? buildDarkTheme() : buildTheme(),
          locale: Locale(language.code), supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [AppLocalizations.delegate, GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
          home: const Scaffold(body: Column(children: [
            PlayUpdateProgress(state: PlayUpdateState(stage: 'downloading', bytes: 25, total: 100)),
            TextField(key: Key('input')),
          ]))));
        await tester.enterText(find.byKey(const Key('input')), 'Samsung S25');
        await tester.pump();
        expect(find.text('25%'), findsOneWidget); expect(find.text('Samsung S25'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}

class _FakeUpdates extends PlayUpdates {
  final actions = <String>[];
  @override
  Future<void> initialize() async {}
  void publish(PlayUpdateState next) { state = next; notifyListeners(); }
  @override
  Future<void> action(String name) async {
    actions.add(name);
    publish(PlayUpdateState(version: state.version, stage: state.stage));
  }
}
