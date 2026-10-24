import 'dart:async';
import 'package:warranty_cave/presentation/app_controller.dart';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warranty_cave/data/account_local_store.dart';
import 'package:warranty_cave/domain/category_entry.dart';
import 'package:warranty_cave/domain/category_catalog.dart';
import 'package:warranty_cave/domain/models.dart';
import 'package:warranty_cave/l10n/app_localizations.dart';
import 'package:warranty_cave/l10n/category_translations.dart';
import 'package:warranty_cave/l10n/additional_translations.dart';
import 'plan_edit_access_test.dart' show controllerWith, warranty;

Future<void> ready(AppController app) async {
  if (app.deferredServicesReady) return;
  final done = Completer<void>();
  void changed() { if (app.deferredServicesReady && !done.isCompleted) done.complete(); }
  app.addListener(changed);
  try { await done.future.timeout(const Duration(seconds: 5)); }
  finally { app.removeListener(changed); }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('EUR is default only without a saved preference; historic item values stay intact', () {
    expect(const AppSettings().defaultCurrency, 'EUR');
    expect(AppSettings.fromJson({}).defaultCurrency, 'EUR');
    for (final currency in ['MKD','USD','EUR']) {
      expect(AppSettings.fromJson({'defaultCurrency': currency}).defaultCurrency, currency);
      final json = {...warranty(1, PlanTier.free).toJson(), 'currency': currency, 'purchasePrice': 319.5};
      expect(WarrantyItem.fromJson(json).toJson(), json);
    }
    final old = warranty(1, PlanTier.free).toJson()..remove('currency');
    expect(WarrantyItem.fromJson(old).currency, 'MKD');
  });
  for (final language in appLanguages) {
    test('${language.code}: every type/group/management label explicitly translated', () {
      final l = AppLocalizations(appLocale(language.code));
      final dictionary = {...?additionalTranslations[language.code], ...?categoryTranslations[language.code]};
      for (final key in {...productTypes.map((e) => e.name), ...productTypes.map((e) => e.category), ...categoryTranslations['en']!.keys}) {
        expect(dictionary[key], isNotNull, reason: '${language.code}: $key');
        expect(l.text(key).trim(), isNotEmpty);
      }
      final s = AppSettings(categories: {'Phone': const CategoryEntry(name: 'My custom phone', revision: '1')});
      expect(l.productLabel('Phone', s), 'My custom phone');
      expect(l.productLabel('My legacy category', s), 'My legacy category');
    });
  }
  test('rename preserves IDs, mandatory type, photos, currency and plan origin', () async {
    final app = await controllerWith([warranty(1, PlanTier.plus)], PlanTier.plus);
    await ready(app);
    final original = app.items.single.toJson();
    await app.saveCategory(id: 'Phone', name: 'Telefonino');
    expect(app.items.single.toJson(), original);
    expect(AppLocalizations(const Locale('it')).productLabel('Phone', app.settings), 'Telefonino');
    final id = await app.saveCategory(name: 'Bicicletta');
    expect(id, startsWith('user:'));
    expect(categoryIds(app.settings, app.items), contains(id));
    expect(AppSettings.fromJson(app.settings.toJson()).categories[id]!.name, 'Bicicletta');
    app.dispose();
  });
  test('deletion moves all warranties and aliases repair offline/legacy records', () async {
    final app = await controllerWith([warranty(1, PlanTier.plus), warranty(2, PlanTier.free)], PlanTier.free);
    await ready(app);
    final old = app.items.map((e) => e.toJson()).toList();
    await app.saveCategory(id: 'Phone', name: 'Telefono', replacement: 'Tablet');
    expect(app.items.length, 2);
    for (var i = 0; i < app.items.length; i++) {
      expect(app.items[i].toJson(), {...old[i], 'productType': 'Tablet'});
    }
    expect(categoryIds(app.settings, app.items), isNot(contains('Phone')));
    expect(normalizeItemCategory(WarrantyItem.fromJson(old.first), app.settings).productType, 'Tablet');
    await app.saveCategory(id: 'Tablet', name: 'Tablet', replacement: 'Computer');
    expect(resolveCategory('Phone', app.settings.categories), 'Computer');
    await expectLater(app.saveCategory(id: 'Other', name: 'Other', replacement: 'Computer'), throwsFormatException);
    await expectLater(app.saveCategory(id: 'Computer', name: 'PC', replacement: 'Computer'), throwsFormatException);
    app.dispose();
  });
  test('offline merge keeps tombstones, newer names, independent additions, and terminates cycles', () {
    const deleted = CategoryEntry(name: 'Old', revision: '2', replacement: 'Tablet');
    const renamed = CategoryEntry(name: 'New', revision: '3');
    final merged = mergeCategories({'Phone': deleted, 'Computer': renamed}, {
      'Phone': const CategoryEntry(name: 'Stale offline rename', revision: '9'),
      'user:new': const CategoryEntry(name: 'Bicycle', revision: '1'),
    });
    expect(merged['Phone'], deleted); expect(merged['Computer'], renamed);
    expect(merged['user:new']!.name, 'Bicycle');
    expect(resolveCategory('Phone', {...merged, 'Tablet': const CategoryEntry(name: 'Cycle', revision: '4', replacement: 'Phone')}), 'Other');
    expect(decodeCategories(encodeCategories(merged))['Phone']!.replacement, 'Tablet');
  });
  test('categories survive restart and guest adoption without leaking between accounts', () async {
    final dir = await Directory.systemTemp.createTemp('categories-');
    addTearDown(() => dir.delete(recursive: true));
    var store = AccountLocalStore(directory: dir);
    await store.activate(null);
    await store.save([warranty(1, PlanTier.free)], const AppSettings(categories: {
      'user:guest': CategoryEntry(name: 'Guest custom', revision: '1'),
      'Phone': CategoryEntry(name: 'Guest phone', revision: '1'),
    }));
    store = AccountLocalStore(directory: dir);
    expect((await store.activate(null)).$2.categories['user:guest']!.name, 'Guest custom');
    final adopted = await store.activate('A', claimGuest: true);
    expect(adopted.$2.categories.length, 2);
    expect((await store.activate(null)).$2.categories, isEmpty);
    expect((await store.activate('B')).$2.categories, isEmpty);
    expect((await store.activate('A')).$2.categories.length, 2);
  });
}
