import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:warranty_cave/data/services.dart';
import 'package:warranty_cave/domain/models.dart';
import 'package:warranty_cave/l10n/app_localizations.dart';
import 'package:warranty_cave/presentation/screens/upgrade_screen.dart';
import 'package:warranty_cave/presentation/theme.dart';

import 'plan_edit_access_test.dart' show controllerWith;

class _StorePrices extends LocalSubscriptionService {
  @override
  String priceFor(PlanTier tier) => switch (tier) {
    PlanTier.basic => '2,99 €',
    PlanTier.plus => '5,99 €',
    PlanTier.free => super.priceFor(tier),
  };
}

void main() {
  testWidgets('store prices retain their currency and show the annual period', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final app = await controllerWith(
      [],
      PlanTier.free,
      subscriptions: _StorePrices(),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: app,
        child: MaterialApp(
          theme: buildDarkTheme(),
          locale: const Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.4),
            ),
            child: child!,
          ),
          home: UpgradeScreen(onSelectTab: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final basic = find.text('2,99 € / Jahr');
    final plus = find.text('5,99 € / Jahr');
    final list = find.byType(Scrollable);
    await tester.scrollUntilVisible(basic, 180, scrollable: list);
    await Scrollable.ensureVisible(tester.element(basic), alignment: 0.35);
    await tester.pumpAndSettle();
    expect(basic.hitTestable(), findsOneWidget);
    await tester.tap(basic);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(plus, 180, scrollable: list);
    expect(plus, findsOneWidget);

    final notice = find.text(
      'Jahresabo · Verlängert sich automatisch. '
      'Jederzeit in Google Play kündbar.',
    );
    await tester.scrollUntilVisible(notice, 180, scrollable: list);
    expect(notice, findsOneWidget);
    final action = find.text('Weiter mit Basic — 2,99 € / Jahr');
    await tester.scrollUntilVisible(action, 180, scrollable: list);
    expect(action, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('fallback prices are amounts, ready for one localized period', () {
    final local = LocalSubscriptionService();
    expect(local.priceFor(PlanTier.basic), '\$2.99');
    expect(local.priceFor(PlanTier.plus), '\$5.99');
  });
}
