import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warranty_cave/presentation/compact_header.dart';
import 'package:warranty_cave/presentation/screens/upgrade_screen.dart';
import 'package:warranty_cave/presentation/theme.dart';
import 'package:warranty_cave/presentation/widgets.dart';

void main() {
  testWidgets('Bold Text keeps Items search beside its heading', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var searches = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme().copyWith(platform: TargetPlatform.iOS),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(boldText: true),
          child: child!,
        ),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: CaveHeader(
              title: 'My Items',
              subtitle: 'Everything in order',
              actions: [
                IconButton(
                  onPressed: () => searches++,
                  icon: const Icon(Icons.search),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final heading = tester.getRect(find.byType(CaveHeader));
    final search = tester.getRect(find.byType(IconButton));
    expect(search.height, greaterThanOrEqualTo(48));
    expect(search.center.dy, closeTo(heading.center.dy, 1));
    expect(search.right, lessThanOrEqualTo(370));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byIcon(Icons.search));
    expect(searches, 1);
  });

  for (final width in [320.0, 390.0]) {
    testWidgets('iOS Bold Text preserves content at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme().copyWith(platform: TargetPlatform.iOS),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              boldText: true,
              textScaler: const TextScaler.linear(1.6),
            ),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    CaveHeader(
                      title: 'Мои производи',
                      subtitle: 'Сè подредено тука',
                      actions: [
                        TextButton(
                          onPressed: () {},
                          child: const Text('Додај'),
                        ),
                      ],
                    ),
                    SectionTitle(
                      'Неодамна додадени',
                      action: TextButton(
                        onPressed: () {},
                        child: const Text('Види ги сите'),
                      ),
                    ),
                    const PlanPriceHeading(
                      title: 'Plus',
                      price: '5,99 € / Jahr',
                      selected: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final label in [
        'Мои производи',
        'Неодамна додадени',
        '5,99 € / Jahr',
      ]) {
        final finder = find.text(label);
        expect(finder, findsOneWidget);
        expect(MediaQuery.boldTextOf(tester.element(finder)), isTrue);
        final paragraph = tester.renderObject<RenderParagraph>(finder);
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(tester.getRect(finder).left, greaterThanOrEqualTo(20));
        expect(tester.getRect(finder).right, lessThanOrEqualTo(width - 20));
      }
    });
  }
}
