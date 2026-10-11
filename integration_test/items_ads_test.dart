import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:warranty_cave/data/ad_service.dart';
import 'package:warranty_cave/data/services.dart';
import 'package:warranty_cave/domain/models.dart';
import 'package:warranty_cave/l10n/app_localizations.dart';
import 'package:warranty_cave/presentation/app_controller.dart';
import 'package:warranty_cave/presentation/screens/items_screen.dart';
import 'package:warranty_cave/presentation/theme.dart';

/// A local-only test harness: no Firebase accounts, writes, or real purchases.
/// The banners themselves use the real Android SDK and Google's sample IDs.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native test banners and entitlement visibility', (tester) async {
    expect(AdService.inlineBannerId, 'ca-app-pub-3940256099942544/9214589741');
    final app = AppController(storage: _Storage(), photos: _Photos(),
      notifications: _Notifications(), subscriptions: LocalSubscriptionService());
    await app.initialize();
    final fixtures = [...app.items];
    app.items = [];
    final dark = ValueNotifier(false);
    await tester.pumpWidget(ChangeNotifierProvider.value(value: app,
      child: ValueListenableBuilder(valueListenable: dark, builder: (context, value, _) => MaterialApp(
        theme: value ? buildDarkTheme() : buildTheme(),
        localizationsDelegates: const [AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: ItemsScreen(onSelectTab: (_) {}),
          bottomNavigationBar: context.watch<AppController>().effectivePlan.hasAds ? const FreeBannerAd() : null),
      )),
    ));
    Future<void> tick([int times = 5]) async {
      for (var i = 0; i < times; i++) { await tester.pump(const Duration(milliseconds: 200)); }
    }
    Future<void> count(int value) async {
      app.items = fixtures.take(value).toList(); app.notifyListeners(); await tick();
    }

    if (const bool.fromEnvironment('ADS_OFFLINE_TEST')) {
      var hasNetwork = false;
      try {
        final socket = await Socket.connect('www.google.com', 443, timeout: const Duration(seconds: 3));
        socket.destroy(); hasNetwork = true;
      } catch (_) { /* Network deliberately disabled by the runner. */ }
      expect(hasNetwork, isFalse, reason: 'Offline fixture must have no network');
      await count(10); await tick(80);
      expect(find.text('Advertisement'), findsNothing);
      await tester.tap(find.byTooltip('Search warranties')); await tick();
      await tester.enterText(find.byType(TextField), 'Warranty 1'); await tick();
      expect(find.text('Warranty 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } else {
      for (final value in [0, 3]) {
        await count(value);
        expect(find.text('Advertisement'), findsNothing);
      }
      await count(4);
      for (var i = 0; i < 150 && find.text('Advertisement').evaluate().isEmpty; i++) { await tick(1); }
      expect(find.text('Advertisement'), findsOneWidget, reason: 'Real Google sample inline ad loaded');
      await binding.convertFlutterSurfaceToImage();
      Future<void> capture(String name) async {
        await tester.pump();
        final bytes = await binding.takeScreenshot(name);
        final root = await getExternalStorageDirectory();
        final folder = Directory('${root!.path}/ads-previews');
        await folder.create(recursive: true);
        await File('${folder.path}/$name.png').writeAsBytes(bytes);
      }
      await capture('WarrantyCave-My-Items-4-Free-light');
      for (final value in [8, 10]) {
        await count(value); await tick(70);
        // The lazy list only builds rows near the viewport; scroll to the second.
        await tester.drag(find.byType(ListView).first, const Offset(0, -650)); await tick(10);
        expect(find.byKey(const ValueKey('ad:2')), findsOneWidget);
        await tester.drag(find.byType(ListView).first, const Offset(0, 900)); await tick(10);
      }
      await tester.tap(find.byTooltip('Search warranties')); await tick();
      await tester.enterText(find.byType(TextField), 'Warranty 1'); await tick();
      expect(find.text('Advertisement'), findsNothing);
      await tester.tap(find.byTooltip('Clear search')); await tick();
      dark.value = true; await tick();
      expect(find.text('Advertisement'), findsWidgets);
      await capture('WarrantyCave-My-Items-Free-dark');
      // This is the same reactive entitlement gate used after purchase/restore.
      for (final plan in [PlanTier.basic, PlanTier.plus]) {
        app.settings = app.settings.copyWith(plan: plan); app.notifyListeners(); await tick();
        expect(find.text('Advertisement'), findsNothing);
        expect(find.byType(FreeBannerAd), findsNothing);
      }
      await capture('WarrantyCave-My-Items-Plus-no-ads');
      expect(app.items.length, 10);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox()); app.dispose(); dark.dispose();
  });
}

class _Storage implements LocalStorageService {
  @override
  Future<(List<WarrantyItem>, AppSettings)> load() async => (
    [for (var i = 0; i < 10; i++) WarrantyItem(id: '$i', productType: 'Other',
      productName: 'Warranty $i', brand: 'Demo', model: 'Model',
      purchaseDate: DateTime(2026, 9, 20), expiryDate: DateTime(2027, 9, 20),
      durationLabel: '1 year', createdAt: DateTime(2026, 9, 30, 12, i))],
    const AppSettings(onboardingComplete: true),
  );
  @override
  Future<void> save(List<WarrantyItem> items, AppSettings settings) async {}
}
class _Photos implements PhotoStorageService {
  @override
  Future<String?> capture(ImageSource source, String itemId, String kind) async => null;
  @override
  Future<void> delete(String path) async {}
}
class _Notifications implements NotificationService {
  @override
  Future<void> cancelFor(String itemId) async {}
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> scheduleFor(WarrantyItem item, AppSettings settings) async {}
}
