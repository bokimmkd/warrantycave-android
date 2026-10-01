import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:warranty_cave/data/services.dart';
import 'package:warranty_cave/domain/models.dart';
import 'package:warranty_cave/l10n/app_localizations.dart';
import 'package:warranty_cave/presentation/app_controller.dart';
import 'package:warranty_cave/presentation/screens/home_screen.dart';
import 'package:warranty_cave/presentation/screens/items_screen.dart';
import 'package:warranty_cave/presentation/screens/reminders_screen.dart';
import 'package:warranty_cave/presentation/screens/settings_screen.dart';
import 'package:warranty_cave/presentation/theme.dart';
import 'package:warranty_cave/presentation/widgets.dart';

const _screenKey = Key('screen');
const _bannerKey = Key('reserved-banner');

Widget _page(int index) => switch (index) {
  0 => HomeScreen(onAdd: () {}, onSeeAll: () {},
    onStatusSelected: (_) {}, onSelectTab: (_) {}),
  1 => ItemsScreen(onSelectTab: (_) {}),
  2 => const RemindersScreen(),
  _ => SettingsScreen(onSelectTab: (_) {}),
};

Future<AppController> _render(WidgetTester tester, int page, {
  double width = 390, double scale = 1, bool dark = false,
  String language = 'en', double keyboard = 0,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  final controller = AppController(storage: _Storage(), photos: _Photos(),
    notifications: _Notifications(), subscriptions: LocalSubscriptionService());
  await controller.initialize();
  await tester.pumpWidget(ChangeNotifierProvider.value(value: controller,
    child: MaterialApp(
      theme: dark ? buildDarkTheme() : buildTheme(),
      locale: Locale(language), supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale),
          viewInsets: EdgeInsets.only(bottom: keyboard)), child: child!),
      home: RepaintBoundary(key: _screenKey, child: Scaffold(
        body: _page(page),
        bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
          if (keyboard == 0) Container(key: _bannerKey, height: 50,
            color: dark ? const Color(0xFF263A4E) : const Color(0xFFEAF4FB),
            alignment: Alignment.center,
            child: const Text('AdMob banner · reserved space', style: TextStyle(fontSize: 11))),
          AppBottomNavigation(selectedIndex: page < 2 ? page : page + 1,
            onSelected: (_) {}),
        ]),
      )),
    )));
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Preview tests run without Android's native UMP implementation.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'plugins.flutter.io/google_mobile_ads/ump',
          (_) async => const StandardMethodCodec().encodeSuccessEnvelope(null),
        );
    final fonts = FontLoader('Roboto')
      ..addFont(rootBundle.load('assets/fonts/DejaVuSans.ttf'));
    await fonts.load();
  });
  for (final page in [0, 1, 2, 3]) {
    testWidgets('compact tab $page stays above reserved banner', (tester) async {
      final controller = await _render(tester, page);
      expect(tester.takeException(), isNull);
      if (page < 2) {
        final first = find.byType(WarrantyCard).first;
        expect(tester.getSize(first).height, lessThan(85));
        expect(tester.getBottomRight(first).dy,
          lessThanOrEqualTo(tester.getTopLeft(find.byKey(_bannerKey)).dy));
      }
      if (Platform.environment['CAPTURE_UI'] == 'true') {
        await expectLater(find.byKey(_screenKey), matchesGoldenFile('captures/tab-$page.png'));
      }
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    testWidgets('tab $page handles narrow dark screen and large translated text', (tester) async {
      for (final code in ['en', 'mk', 'de', 'es', 'fr', 'it', 'tr', 'el']) {
        final controller = await _render(tester, page, width: 320, scale: 1.5,
          dark: true, language: code);
        expect(tester.takeException(), isNull, reason: 'tab $page / $code');
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  for (final page in [0, 1]) {
    testWidgets('tab $page search filters and closing restores items', (tester) async {
      final controller = await _render(tester, page);
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.byTooltip('Search warranties'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Samsung');
      await tester.pumpAndSettle();
      expect(find.text('Mac Neo'), findsNothing);
      expect(find.text('Samsung S25'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Mac Neo'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }
}

class _Storage implements LocalStorageService {
  @override
  Future<(List<WarrantyItem>, AppSettings)> load() async => (
    [for (final (i, name, brand, model) in [
      (0, 'Samsung S25', 'Samsung', 'S25'),
      (1, 'Mac Neo', 'Apple', 'Neo'),
      (2, 'StarLink', 'StarLink', 'Router'),
      (3, 'Coffee machine', 'Kitchen', 'Daily'),
      (4, 'Headphones', 'Audio', 'Wireless'),
      (5, 'Vacuum cleaner', 'Home', 'Compact'),
    ]) WarrantyItem(id: '$i', productType: 'Other', productName: name,
      brand: brand, model: model, purchaseDate: DateTime(2026, 9, 20),
      expiryDate: DateTime(2027, 9, 20), durationLabel: '1 year',
      createdAt: DateTime(2026, 9, 30, 12, 6 - i))],
    const AppSettings(onboardingComplete: true, firstName: 'Aleksandar',
      lastName: 'Petreski', email: 'demo@example.com'),
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
