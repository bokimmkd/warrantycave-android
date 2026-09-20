import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warranty_cave/l10n/app_localizations.dart';

void main() {
  test('every localization key used by the UI resolves in every locale', () {
    final keyPattern = RegExp(r"l10n\.(?:text|format)\('([^']+)'");
    final keys = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .expand(
          (file) => keyPattern
              .allMatches(file.readAsStringSync())
              .map((match) => match.group(1)!),
        )
        .toSet();

    expect(keys, isNotEmpty);
    for (final locale in AppLocalizations.supportedLocales) {
      final translations = AppLocalizations(locale);
      for (final key in keys) {
        expect(
          translations.text(key),
          isNot(key),
          reason: '${locale.languageCode} does not resolve $key',
        );
      }
    }
  });

  test('secondary screen copy has no accidental English fallback', () {
    const keys = [
      'signOutInfo',
      'deleteAccountInfo',
      'syncSecurely',
      'deleteProductPhotoInfo',
      'chooseTypeContinue',
      'saveFailed',
      'shareWarrantyText',
      'claimPackTitle',
      'claimPackFailed',
      'scanPackInfo',
      'freeLimitReached',
      'invalidCredentials',
    ];
    final english = AppLocalizations(const Locale('en'));
    for (final code in ['mk', 'de', 'es', 'fr', 'it', 'tr', 'el']) {
      final translations = AppLocalizations(Locale(code));
      for (final key in keys) {
        expect(
          translations.text(key),
          isNot(english.text(key)),
          reason: '$code falls back to English for $key',
        );
      }
    }
  });
}
