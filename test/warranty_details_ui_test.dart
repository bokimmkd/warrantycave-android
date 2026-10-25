import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:warranty_cave/data/services.dart';
import 'package:warranty_cave/domain/models.dart';
import 'package:warranty_cave/l10n/app_localizations.dart';
import 'package:warranty_cave/presentation/app_controller.dart';
import 'package:warranty_cave/presentation/screens/item_detail_screen.dart';
import 'package:warranty_cave/presentation/theme.dart';
import 'package:warranty_cave/presentation/widgets.dart';
import 'guest_accounts_test.dart' as fakes;

class _Storage extends Fake implements LocalStorageService {
  _Storage(this.item);
  final WarrantyItem item;
  @override
  Future<(List<WarrantyItem>, AppSettings)> load() async =>
      ([item], const AppSettings(plan: PlanTier.plus));
  @override
  Future<void> save(List<WarrantyItem> items, AppSettings settings) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late WarrantyItem item;
  final controllers = <AppController>[];
  setUpAll(() async {
    final fonts = FontLoader('Roboto')
      ..addFont(rootBundle.load('assets/fonts/DejaVuSans.ttf'));
    await fonts.load();
    dir = await Directory.systemTemp.createTemp('wc-detail-preview-');
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');
    for (final name in ['product', 'receipt', 'receipt2', 'warranty']) {
      await File('${dir.path}/$name.png').writeAsBytes(bytes);
    }
    item = WarrantyItem(
      id: 'details', productType: 'Car Electronics / Accessories',
      productName: 'BMW 1600', brand: 'BMW', model: '1600',
      serialNumber: 'SERIAL-12345678901234567890',
      store: 'Andrej Kompani', authorizedService: 'Authorized service',
      servicePhone: '070210103', serviceEmail: 'long-service-name@example.com',
      location: 'Home', purchasePrice: 6993, currency: 'MKD',
      purchaseDate: DateTime(2026, 10, 6), expiryDate: DateTime(2027, 10, 6),
      durationLabel: '1 year', createdAt: DateTime(2026, 10, 6),
      isExtendedWarranty: true, notes: 'Warranty notes',
      productPhoto: '${dir.path}/product.png',
      receiptPhotos: ['${dir.path}/receipt.png', '${dir.path}/receipt2.png'],
      warrantyPhotos: ['${dir.path}/warranty.png'],
    );
  });
  tearDownAll(() async { await dir.delete(recursive: true); });
  tearDown(() {
    for (final controller in controllers) { controller.dispose(); }
    controllers.clear();
  });

  Future<void> render(WidgetTester tester, {
    String language = 'mk', bool dark = false,
    double width = 390, double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = AppController(
      storage: _Storage(item), photos: fakes.Photos(),
      notifications: fakes.Notifications(),
      subscriptions: LocalSubscriptionService(),
    );
    controllers.add(controller);
    await controller.initialize();
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: controller,
      child: MaterialApp(
        locale: appLocale(language),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate, GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
        ],
        theme: dark ? buildDarkTheme() : buildTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            padding: const EdgeInsets.only(bottom: 24),
            viewPadding: const EdgeInsets.only(bottom: 24),
          ), child: child!),
        home: const RepaintBoundary(key: Key('detail-capture'),
          child: ItemDetailScreen(itemId: 'details', onSelectTab: null)),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('all fields retained; contact appears once and product opens from header', (tester) async {
    await render(tester);
    expect(find.text(item.servicePhone), findsOneWidget);
    expect(find.text(item.serviceEmail), findsOneWidget);
    final table = tester.widget<Table>(find.byKey(const Key('warranty-details-table')));
    expect(table.children.length, 12);
    for (final scheme in ['tel', 'mailto']) {
      final contact = find.byKey(Key('warranty-contact-$scheme'));
      expect(tester.getSize(contact).height, greaterThanOrEqualTo(48));
      expect(tester.widget<InkWell>(contact).onTap, isNotNull);
    }
    final ctx = tester.element(find.byType(ItemDetailScreen));
    expect(find.text(ctx.l10n.text('extendedWarrantyBadge')), findsOneWidget);
    expect(find.byType(AppBottomNavigation), findsOneWidget);
    await tester.tap(find.byKey(const Key('product-photo-preview')));
    await tester.pumpAndSettle();
    expect(find.text('1 of 1'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('receipt and warranty thumbnails open all attachments with zoom', (tester) async {
    await render(tester);
    for (final entry in [('receipt-photo-attachment', '1 of 2'), ('warranty-photo-attachment', '1 of 1')]) {
      await tester.scrollUntilVisible(find.byKey(Key(entry.$1)), 220,
        scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byKey(Key(entry.$1)));
      await tester.pumpAndSettle();
      expect(find.text(entry.$2), findsOneWidget);
      if (entry.$1 == 'receipt-photo-attachment') {
        await tester.drag(find.byType(PageView), const Offset(-350, 0));
        await tester.pumpAndSettle();
        expect(find.text('2 of 2'), findsOneWidget);
      }
      Navigator.of(tester.element(find.byType(PageView))).pop();
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets('detail light-dark compact captures $dark', (tester) async {
      await render(tester, dark: dark);
      if (Platform.environment['CAPTURE_UI'] == 'true') {
        await expectLater(find.byKey(const Key('detail-capture')),
          matchesGoldenFile('captures/details-${dark ? 'dark' : 'light'}-top.png'));
      }
      final ctx = tester.element(find.byType(ItemDetailScreen));
      await tester.scrollUntilVisible(find.text(ctx.l10n.text('deleteWarrantyLabel')), 220,
        scrollable: find.byType(Scrollable).first);
      if (Platform.environment['CAPTURE_UI'] == 'true') {
        await expectLater(find.byKey(const Key('detail-capture')),
          matchesGoldenFile('captures/details-${dark ? 'dark' : 'light'}-bottom.png'));
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('narrow screen and large translated text keep all details and actions readable', (tester) async {
    for (final language in ['en','mk','de','es','fr','it','tr','el','pl','cs','pt-PT','pt-BR']) {
      for (final dark in [false, true]) {
        await render(tester, language: language, width: 320, scale: 1.5, dark: dark);
        final ctx = tester.element(find.byType(ItemDetailScreen));
        await tester.scrollUntilVisible(find.text(ctx.l10n.text('deleteWarrantyLabel')), 200,
          scrollable: find.byType(Scrollable).first);
        expect(tester.takeException(), isNull, reason: '$language dark=$dark');
        expect(tester.getBottomRight(find.text(ctx.l10n.text('deleteWarrantyLabel'))).dy,
          lessThan(tester.getTopLeft(find.byType(AppBottomNavigation)).dy));
        await tester.pumpWidget(const SizedBox());
      }
    }
  });
}
