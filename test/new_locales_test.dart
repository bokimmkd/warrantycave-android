import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warranty_cave/l10n/app_localizations.dart';
import 'package:warranty_cave/l10n/additional_translations.dart';

void main() {
  final english = jsonDecode(File('tool/english-reference.json').readAsStringSync()) as Map<String, dynamic>;
  for (final code in ['pl', 'cs', 'pt-PT', 'pt-BR']) {
    test('$code has explicit translations and retains all template arguments', () {
      final dictionary = additionalTranslations[code]!;
      final translations = AppLocalizations(appLocale(code));
      final placeholders = RegExp(r'\{\w+\}');
      for (final entry in english.entries) {
        expect(dictionary.containsKey(entry.key), isTrue, reason: '$code ${entry.key}');
        expect(translations.text(entry.key), dictionary[entry.key]);
        expect(placeholders.allMatches(dictionary[entry.key]!).map((m) => m[0]).toList()..sort(),
          placeholders.allMatches(entry.value as String).map((m) => m[0]).toList()..sort(), reason: '$code ${entry.key}');
      }
      expect(translations.duration('13 months (custom)'), contains('13'));
      expect(translations.duration('my custom warranty'), 'my custom warranty');
      expect(translations.productLabel('home'), 'home');
      expect(translations.productLabel('My custom label'), 'My custom label');
      for (final days in [0, 1, 2, 5, 21]) {
        final body = translations.format('notificationDays', {'product': 'Test', 'days': days});
        expect(body, contains('Test')); expect(body, contains('$days'));
        expect(body, isNot(contains('{')));
      }
    });
  }
  test('Portuguese regions resolve separately and survive settings format', () {
    expect(appLocale('pt-BR'), const Locale('pt', 'BR'));
    expect(appLocale('pt_PT'), const Locale('pt', 'PT'));
    expect(AppLocalizations(appLocale('pt-BR')).text('settings'), 'Configurações');
    expect(AppLocalizations(appLocale('pt-PT')).text('settings'), 'Definições');
    expect(AppLocalizations(const Locale('pt')).text('settings'), 'Definições');
    expect(appLanguages.any((l) => l.code == 'ru'), isFalse);
    expect(AppLocalizations(const Locale('en')).text('unknownUserText'), 'unknownUserText');
  });
}
