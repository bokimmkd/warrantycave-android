import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warranty_cave/l10n/app_localizations.dart';
import 'package:warranty_cave/l10n/navigation_labels.dart';
import 'package:warranty_cave/presentation/theme.dart';
import 'package:warranty_cave/presentation/widgets.dart';

const _keys = ['home', 'items', 'add', 'reminders', 'settings'];
const _capture = Key('navigation-capture');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/DejaVuSans.ttf')))
        .load();
    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    if (flutterRoot != null) {
      final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
      if (icons.existsSync()) {
        await (FontLoader('MaterialIcons')
              ..addFont(Future.value(ByteData.sublistView(await icons.readAsBytes()))))
            .load();
      }
    }
  });

  for (final locale in AppLocalizations.supportedLocales) {
    for (final dark in [false, true]) {
      testWidgets('${locale.toLanguageTag()} navigation stays on one line dark=$dark', (tester) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final l10n = AppLocalizations(locale);
        for (final width in [320.0, 390.0]) {
          tester.view.physicalSize = Size(width, 250);
          for (final scale in [1.0, 1.5]) {
            for (final selected in [0, 3, 4]) {
              var destination = -1;
              await tester.pumpWidget(MaterialApp(
                theme: dark ? buildDarkTheme() : buildTheme(),
                locale: locale,
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  bottomNavigationBar: RepaintBoundary(
                    key: _capture,
                    child: AppBottomNavigation(
                      selectedIndex: selected,
                      onSelected: (index) => destination = index,
                    ),
                  ),
                ),
              ));
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              for (var index = 0; index < _keys.length; index++) {
                final key = _keys[index];
                final label = find.text(l10n.navigationLabel(key));
                expect(label, findsOneWidget);
                final rich = find.descendant(of: label, matching: find.byType(RichText));
                final paragraph = tester.renderObject<RenderParagraph>(rich);
                final painter = TextPainter(
                  text: paragraph.text,
                  textDirection: paragraph.textDirection,
                  textScaler: paragraph.textScaler,
                )..layout(maxWidth: paragraph.size.width);
                expect(painter.computeLineMetrics().length, 1,
                    reason: '${locale.toLanguageTag()} $key width=$width scale=$scale selected=$selected');
                expect(painter.width, lessThanOrEqualTo(paragraph.size.width));
                expect(tester.widget<Text>(label).style!.fontSize, 11,
                    reason: 'Never shrink the existing label font');
                painter.dispose();
                final tile = find.byType(NavigationDestination).at(index);
                expect(tester.getSize(tile).width, greaterThanOrEqualTo(48));
                expect(tester.getSize(tile).height, greaterThanOrEqualTo(48));
                expect(tester.widget<NavigationDestination>(tile).tooltip, l10n.text(key));
                await tester.tap(tile);
                expect(destination, index);
              }
              if (Platform.environment['CAPTURE_UI'] == 'true' && scale == 1 && selected == 4) {
                await expectLater(find.byKey(_capture), matchesGoldenFile(
                  'captures/nav-${locale.toLanguageTag()}-$dark-${width.toInt()}.png'));
              }
            }
          }
        }
      });
    }
  }
}
