import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warranty_cave/l10n/app_localizations.dart';
import 'package:warranty_cave/presentation/account_actions.dart';
import 'package:warranty_cave/presentation/meta_measurement_choice.dart';
import 'package:warranty_cave/presentation/theme.dart';

Widget _app(Widget child, {String language = 'en', bool dark = false, double scale = 1}) =>
  MaterialApp(theme: dark ? buildDarkTheme() : buildTheme(), locale: Locale(language),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate],
    builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(scale)), child: child!),
    home: Scaffold(body: Center(child: SizedBox(width: 288, child: child))));

void main() {
  const channel = MethodChannel('com.warrantycave.app/meta_app_events');
  final choices = <bool>[];
  setUp(() {
    choices.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getConsent') return false;
        if (call.method == 'setConsent') choices.add(call.arguments['enabled'] as bool);
        return null;
      });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
    .setMockMethodCallHandler(channel, null));

  testWidgets('account actions stay in one row with distinct targets in all languages', (tester) async {
    for (final dark in [false, true]) {
      for (final locale in AppLocalizations.supportedLocales) {
        var signedOut = 0;
        var deleted = 0;
        final l10n = AppLocalizations(locale);
        await tester.pumpWidget(_app(AccountActions(onSignOut: () => signedOut++,
          onDelete: () => deleted++), language: locale.languageCode, dark: dark, scale: 1.5));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '${locale.languageCode}/$dark');
        final signOut = find.text(l10n.text('signOut'));
        final delete = find.text(l10n.text('deleteAccount'));
        expect(tester.getCenter(signOut).dx, lessThan(tester.getCenter(delete).dx));
        for (final target in find.byType(InkWell).evaluate()) {
          expect(tester.getSize(find.byElementPredicate((element) => element == target)).height,
            greaterThanOrEqualTo(48));
        }
        await tester.tap(signOut);
        expect(signedOut, 1); expect(deleted, 0);
        await tester.tap(delete);
        expect(deleted, 1);
      }
    }
  });

  testWidgets('Meta is off by default; declining sends nothing; accepting enables and revocation disables', (tester) async {
    await tester.pumpWidget(_app(const MetaMeasurementChoice()));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, false);
    expect(choices, isEmpty);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(choices, isEmpty);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Allow'));
    await tester.pumpAndSettle();
    expect(choices, [true]);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(choices, [true, false]);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
