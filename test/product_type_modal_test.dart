import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:warranty_cave/domain/models.dart';
import 'package:warranty_cave/l10n/app_localizations.dart';
import 'package:warranty_cave/presentation/screens/add_warranty_screen.dart';
import 'package:warranty_cave/presentation/screens/categories_screen.dart';
import 'package:warranty_cave/presentation/theme.dart';
import 'categories_test.dart' show ready;
import 'plan_edit_access_test.dart' show controllerWith, warranty;

double contrast(Color foreground, Color background) {
  final fg = Color.alphaBlend(foreground, background).computeLuminance();
  final bg = background.computeLuminance();
  return (fg > bg ? fg + .05 : bg + .05) /
      (fg > bg ? bg + .05 : fg + .05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('Roboto')..addFont(rootBundle.load('assets/fonts/DejaVuSans.ttf'))).load();
    final root = Platform.environment['FLUTTER_ROOT'];
    if (root != null) {
      final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
      if (icons.existsSync()) {
        await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(await icons.readAsBytes())))).load();
      }
    }
  });

  const cases = [
    (code: 'en', dark: false, width: 360.0, height: 800.0, scale: 1.0, edit: false, keyboard: 0.0),
    (code: 'en', dark: true, width: 360.0, height: 800.0, scale: 1.0, edit: false, keyboard: 0.0),
    (code: 'mk', dark: false, width: 360.0, height: 800.0, scale: 1.0, edit: false, keyboard: 0.0),
    (code: 'mk', dark: true, width: 360.0, height: 800.0, scale: 1.0, edit: false, keyboard: 0.0),
    (code: 'pl', dark: true, width: 320.0, height: 640.0, scale: 1.4, edit: false, keyboard: 0.0),
    (code: 'en', dark: true, width: 360.0, height: 800.0, scale: 1.0, edit: true, keyboard: 220.0),
  ];
  for (final spec in cases) {
    final id = '${spec.code}-${spec.dark ? 'dark' : 'light'}-${spec.width.toInt()}-${spec.edit ? 'edit' : 'add'}';
    testWidgets('actual product picker is readable and retains draft $id', (tester) async {
      tester.view.physicalSize = Size(spec.width, spec.height);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final item = warranty(1, PlanTier.free);
      final app = await controllerWith(spec.edit ? [item] : [], PlanTier.free);
      await ready(app);
      final l = AppLocalizations(appLocale(spec.code));
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: app,
        child: RepaintBoundary(
          key: const Key('modalCapture'),
          child: MaterialApp(
            theme: spec.dark ? buildDarkTheme() : buildTheme(),
            locale: appLocale(spec.code),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate, GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
            ],
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(spec.scale),
                padding: const EdgeInsets.only(top: 24, bottom: 24),
                viewPadding: const EdgeInsets.only(top: 24, bottom: 24),
                viewInsets: EdgeInsets.only(bottom: spec.keyboard),
              ),
              child: child!,
            ),
            home: AddWarrantyScreen(existing: spec.edit ? item : null),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final draftName = 'Unsaved product $id';
      await tester.enterText(
        find.widgetWithText(TextFormField, l.text('productNameRequired')), draftName);
      final opener = find.text(spec.edit ? l.productLabel('Phone') : l.text('chooseProductType'));
      await tester.ensureVisible(opener);
      await tester.tap(opener);
      await tester.pumpAndSettle();

      final sheet = find.byType(ProductTypeSheet);
      expect(sheet, findsOneWidget);
      final material = tester.widget<Material>(
        find.ancestor(of: sheet, matching: find.byType(Material)).first);
      final background = material.color!;
      // Check the actual modal surface together with its rendered text.
      // Rendering ProductTypeSheet alone previously missed the pale parent.
      for (final label in [l.text('chooseProductType'), l.text('addCategory'), l.productLabel('Phone')]) {
        final text = find.descendant(of: sheet, matching: find.text(label));
        final rich = tester.widget<RichText>(
          find.descendant(of: text, matching: find.byType(RichText)));
        expect(contrast(rich.text.style!.color!, background),
          greaterThanOrEqualTo(4.5), reason: '$id: $label must contrast with the modal surface');
      }
      expect(tester.takeException(), isNull);
      if (Platform.environment['CAPTURE_UI'] == 'true') {
        await expectLater(find.byKey(const Key('modalCapture')),
          matchesGoldenFile('captures/product-picker-$id.png'));
      }

      await tester.enterText(find.descendant(of: sheet, matching: find.byType(TextField)), l.productLabel('Phone'));
      await tester.pumpAndSettle();
      final phone = find.descendant(of: sheet, matching: find.widgetWithText(ListTile, l.productLabel('Phone')));
      expect(phone, findsOneWidget);
      await tester.ensureVisible(phone);
      await tester.tap(phone);
      await tester.pumpAndSettle();
      expect(find.byType(ProductTypeSheet), findsNothing);
      expect(find.text(draftName), findsOneWidget);
      expect(app.items.length, spec.edit ? 1 : 0);
      if (spec.edit) expect(app.items.single.toJson(), item.toJson());
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    });
  }
}
