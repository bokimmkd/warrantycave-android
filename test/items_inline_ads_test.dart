import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:warranty_cave/data/inline_banner.dart';
import 'package:warranty_cave/data/services.dart';
import 'package:warranty_cave/domain/models.dart';
import 'package:warranty_cave/l10n/app_localizations.dart';
import 'package:warranty_cave/presentation/app_controller.dart';
import 'package:warranty_cave/presentation/items_ad_list.dart';
import 'package:warranty_cave/presentation/screens/items_screen.dart';
import 'package:warranty_cave/presentation/theme.dart';

class _Banner implements InlineBanner {
  _Banner(this.width);
  final int width;
  final result = Completer<Size?>();
  int loads = 0;
  bool disposed = false;
  void succeed() => result.complete(Size(width.toDouble(), 120));
  void fail() => result.complete(null);
  @override
  Future<Size?> load() { loads++; return result.future; }
  @override
  void dispose() { disposed = true; }
  @override
  Widget buildAd() => const ColoredBox(color: Colors.blue,
    child: Center(child: Text('Test ad')));
}

class _Factory {
  final banners = <_Banner>[];
  InlineBanner create(int width, int maxHeight) {
    expect(maxHeight, 250);
    final ad = _Banner(width); banners.add(ad); return ad;
  }
}

Widget _list(_Factory factory, List<String> ids, {bool ads = true,
  bool active = true, bool dark = false, ValueChanged<int>? tap}) => MaterialApp(
  theme: dark ? buildDarkTheme() : buildTheme(),
  home: Scaffold(body: ItemsAdList(itemIds: ids, adsEnabled: ads,
    active: active, bannerFactory: factory.create,
    itemBuilder: (_, i) => SizedBox(height: 60,
      child: InkWell(onTap: () => tap?.call(i), child: Text('Warranty ${ids[i]}')))),
);

Future<void> _finish(WidgetTester tester, _Factory factory) async {
  for (final ad in factory.banners) { if (!ad.result.isCompleted) ad.succeed(); }
  await tester.pumpAndSettle();
}

void main() {
  for (final count in [0, 3, 4, 8, 10]) {
    for (final dark in [false, true]) {
      testWidgets('$count items / ${dark ? "dark" : "light"}: ads after each four', (tester) async {
        tester.view.physicalSize = const Size(390, 1900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final factory = _Factory();
        final ids = [for (var i = 0; i < count; i++) '$i'];
        await tester.pumpWidget(_list(factory, ids, dark: dark));
        await tester.pumpAndSettle();
        expect(factory.banners.length, count ~/ 4);
        expect(find.text('Advertisement'), findsNothing);
        await _finish(tester, factory);
        expect(find.text('Advertisement'), findsNWidgets(count ~/ 4));
        for (var number = 1; number <= count ~/ 4; number++) {
          final ad = find.byKey(ValueKey('ad:$number'));
          final before = find.byKey(ValueKey('item:${number * 4 - 1}'));
          expect(tester.getTopLeft(ad).dy, greaterThanOrEqualTo(tester.getBottomRight(before).dy));
          if (number * 4 < count) {
            final after = find.byKey(ValueKey('item:${number * 4}'));
            expect(tester.getTopLeft(after).dy, greaterThanOrEqualTo(tester.getBottomRight(ad).dy));
          }
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        expect(factory.banners.every((ad) => ad.disposed), isTrue);
      });
    }
  }

  testWidgets('failures leave no ad rows, holes, or redraw retries', (tester) async {
    final factory = _Factory(); final ids = [for (var i = 0; i < 8; i++) '$i'];
    await tester.pumpWidget(_list(factory, ids)); await tester.pumpAndSettle();
    final before = tester.getTopLeft(find.byKey(const ValueKey('item:4'))).dy;
    for (final ad in factory.banners) { ad.fail(); }
    await tester.pumpAndSettle();
    expect(find.text('Advertisement'), findsNothing);
    expect(tester.getTopLeft(find.byKey(const ValueKey('item:4'))).dy, before);
    for (var i = 0; i < 5; i++) {
      await tester.pumpWidget(_list(factory, ids, dark: i.isEven));
      await tester.pumpAndSettle();
    }
    expect(factory.banners.length, 2);
    expect(factory.banners.every((ad) => ad.loads == 1 && ad.disposed), isTrue);
  });

  testWidgets('search, sorting and empty results reuse slots and count the displayed list', (tester) async {
    tester.view.physicalSize = const Size(390, 1900); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final factory = _Factory(); final ids = [for (var i = 0; i < 10; i++) '$i'];
    await tester.pumpWidget(_list(factory, ids)); await tester.pumpAndSettle(); await _finish(tester, factory);
    for (final filtered in [ids.take(3).toList(), <String>[], ids.reversed.take(8).toList(), ids]) {
      await tester.pumpWidget(_list(factory, filtered)); await tester.pumpAndSettle();
      expect(find.text('Advertisement'), findsNWidgets(filtered.length ~/ 4));
    }
    expect(factory.banners.length, 2);
    expect(factory.banners.every((ad) => ad.loads == 1), isTrue);
  });

  testWidgets('paid entitlement removes and disposes ads, including a late callback', (tester) async {
    final factory = _Factory(); final ids = [for (var i = 0; i < 8; i++) '$i'];
    await tester.pumpWidget(_list(factory, ids)); await tester.pumpAndSettle();
    await tester.pumpWidget(_list(factory, ids, ads: false)); await tester.pumpAndSettle();
    await _finish(tester, factory);
    expect(find.text('Advertisement'), findsNothing);
    expect(factory.banners.every((ad) => ad.disposed), isTrue);
    expect(factory.banners.length, 2);
  });

  testWidgets('inactive Items requests no ads and active tab reuses loaded ones', (tester) async {
    final factory = _Factory(); final ids = [for (var i = 0; i < 4; i++) '$i'];
    await tester.pumpWidget(_list(factory, ids, active: false)); await tester.pumpAndSettle();
    expect(factory.banners, isEmpty);
    await tester.pumpWidget(_list(factory, ids)); await tester.pumpAndSettle(); await _finish(tester, factory);
    await tester.pumpWidget(_list(factory, ids, active: false)); await tester.pumpAndSettle();
    expect(find.text('Advertisement'), findsNothing);
    await tester.pumpWidget(_list(factory, ids)); await tester.pumpAndSettle();
    expect(find.text('Advertisement'), findsOneWidget);
    expect(factory.banners.length, 1);
  });

  testWidgets('loading an ad does not move a row under a held finger', (tester) async {
    final factory = _Factory(); final ids = [for (var i = 0; i < 8; i++) '$i'];
    await tester.pumpWidget(_list(factory, ids)); await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('item:4'));
    final before = tester.getTopLeft(row);
    final gesture = await tester.startGesture(tester.getCenter(row));
    await _finish(tester, factory);
    expect(find.text('Advertisement'), findsNothing);
    expect(tester.getTopLeft(row), before);
    await gesture.up(); await tester.pumpAndSettle();
    expect(find.text('Advertisement'), findsWidgets);
  });

  testWidgets('rotation discards old requests and loads once for new width', (tester) async {
    tester.view.physicalSize = const Size(390, 800); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final factory = _Factory(); final ids = [for (var i = 0; i < 4; i++) '$i'];
    await tester.pumpWidget(_list(factory, ids)); await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(320, 800); await tester.pumpAndSettle();
    expect(factory.banners.length, 2); expect(factory.banners.first.disposed, isTrue);
    factory.banners.first.succeed(); await tester.pumpAndSettle();
    expect(find.text('Advertisement'), findsNothing);
    factory.banners.last.succeed(); await tester.pumpAndSettle();
    expect(find.text('Advertisement'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final plan in PlanTier.values) {
    testWidgets('ItemsScreen observes $plan entitlement without changing warranties', (tester) async {
      final factory = _Factory();
      final app = AppController(storage: _Storage(), photos: _Photos(),
        notifications: _Notifications(), subscriptions: LocalSubscriptionService());
      await app.initialize();
      app.settings = app.settings.copyWith(plan: plan);
      await tester.pumpWidget(_screen(app, factory)); await tester.pumpAndSettle();
      expect(factory.banners.length, plan.hasAds ? 2 : 0);
      await _finish(tester, factory);
      if (plan.hasAds) {
        await tester.tap(find.byTooltip('Search warranties')); await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'First'); await tester.pumpAndSettle();
        expect(find.text('Advertisement'), findsNothing);
        await tester.tap(find.byTooltip('Clear search')); await tester.pumpAndSettle();
        expect(factory.banners.length, 2);
        app.settings = app.settings.copyWith(plan: PlanTier.basic); app.notifyListeners();
        await tester.pumpAndSettle();
        expect(find.text('Advertisement'), findsNothing);
        expect(factory.banners.every((ad) => ad.disposed), isTrue);
      }
      expect(app.items.length, 10);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox()); app.dispose();
    });
  }
}

Widget _screen(AppController app, _Factory factory) => ChangeNotifierProvider.value(
  value: app, child: MaterialApp(theme: buildTheme(),
    localizationsDelegates: const [AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: ItemsScreen(onSelectTab: (_) {}, inlineBannerFactory: factory.create)),
  ));

class _Storage implements LocalStorageService {
  @override
  Future<(List<WarrantyItem>, AppSettings)> load() async => (
    [for (var i = 0; i < 10; i++) WarrantyItem(id: '$i', productType: 'Other',
      productName: i < 3 ? 'First $i' : 'Other $i', brand: 'Brand', model: 'Model',
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
