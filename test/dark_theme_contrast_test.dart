import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warranty_cave/presentation/theme.dart';

void main() {
  test('dark cards have readable default text and accent colors', () {
    final theme = buildDarkTheme();
    final surface = theme.colorScheme.surface;
    final body = theme.textTheme.bodyMedium!.color!;
    final price = theme.colorScheme.primary;

    expect(theme.brightness, Brightness.dark);
    expect(_contrast(body, surface), greaterThanOrEqualTo(4.5));
    expect(_contrast(price, surface), greaterThanOrEqualTo(4.5));
  });
}

double _contrast(Color a, Color b) {
  final light = a.computeLuminance();
  final dark = b.computeLuminance();
  return (light > dark ? light + 0.05 : dark + 0.05) /
      (light > dark ? dark + 0.05 : light + 0.05);
}
