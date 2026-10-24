import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:warranty_cave/domain/models.dart';
import 'package:warranty_cave/l10n/app_localizations.dart';
import 'package:warranty_cave/presentation/app_controller.dart';
import 'package:warranty_cave/presentation/screens/add_warranty_screen.dart';
import 'package:warranty_cave/presentation/screens/categories_screen.dart';
import 'package:warranty_cave/presentation/theme.dart';
import 'plan_edit_access_test.dart' show controllerWith, warranty;
import 'categories_test.dart' show ready;

Future<void> render(WidgetTester tester, AppController app, Widget screen, String code, bool dark) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(ChangeNotifierProvider.value(value: app, child: MaterialApp(
    theme: dark ? buildDarkTheme() : buildTheme(),
    locale: appLocale(code), supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [AppLocalizations.delegate, GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
    home: RepaintBoundary(key: const Key('categoryCapture'), child: screen),
  )));
  await tester.pumpAndSettle();
}
void main() {
  for (final code in appLanguages.map((e) => e.code)) {
    for (final dark in [false, true]) {
      testWidgets('category management fits $code dark=$dark', (tester) async {
        final app = await controllerWith([warranty(1, PlanTier.free)], PlanTier.free);
        await ready(app);
        await render(tester, app, const CategoriesScreen(), code, dark);
        final l = AppLocalizations(appLocale(code));
        expect(find.text(l.text('manageCategories')), findsOneWidget);
        expect(find.text(l.productLabel('Phone')), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (Platform.environment['CAPTURE_UI'] == 'true' && ['it','de','pl'].contains(code)) {
          await expectLater(find.byKey(const Key('categoryCapture')),
            matchesGoldenFile('captures/categories-$code-${dark ? 'dark' : 'light'}.png'));
        }
        await tester.pumpWidget(const SizedBox()); app.dispose();
      });
    }
  }
  testWidgets('used category requires replacement and cancellation preserves warranties', (tester) async {
    final app = await controllerWith([warranty(1, PlanTier.free)], PlanTier.free); await ready(app);
    await render(tester, app, const CategoriesScreen(), 'en', false);
    Future<void> openDelete() async {
      await tester.tap(find.descendant(of: find.widgetWithText(ListTile, 'Phone'), matching: find.byType(PopupMenuButton<String>)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete category')); await tester.pumpAndSettle();
    }
    await openDelete();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Delete category')).onPressed, isNull);
    await tester.tap(find.text('Cancel')); await tester.pumpAndSettle();
    expect(app.items.single.productType, 'Phone'); expect(app.settings.categories, isEmpty);
    await openDelete();
    await tester.tap(find.byType(DropdownButtonFormField<String>)); await tester.pumpAndSettle();
    await tester.tap(find.text('Tablet').last); await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete category')); await tester.pumpAndSettle();
    expect(app.items.single.productType, 'Tablet'); expect(app.items.single.id, 'item-1');
    expect(find.widgetWithText(ListTile, 'Phone'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); app.dispose();
  });
  testWidgets('Add shortcut preserves unsaved product and custom category survives language', (tester) async {
    final app = await controllerWith([], PlanTier.free); await ready(app);
    await render(tester, app, const AddWarrantyScreen(), 'en', false);
    await tester.enterText(find.widgetWithText(TextFormField, 'Product Name *'), 'Unsaved bicycle');
    await tester.tap(find.text('Manage categories')); await tester.pumpAndSettle();
    await tester.tap(find.text('Add category')); await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'My bicycle');
    await tester.tap(find.text('Save')); await tester.pumpAndSettle();
    expect(app.settings.categories.values.single.name, 'My bicycle');
    await tester.tap(find.byType(BackButton)); await tester.pumpAndSettle();
    expect(find.text('Unsaved bicycle'), findsOneWidget);
    await tester.tap(find.text(AppLocalizations(const Locale('en')).text('chooseProductType'))); await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'My bicycle'); await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'My bicycle')); await tester.pumpAndSettle();
    expect(find.text('My bicycle'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); app.dispose();
  });
}
