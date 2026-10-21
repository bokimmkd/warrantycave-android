import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:warranty_cave/main.dart' as application;
import 'package:warranty_cave/domain/models.dart';
import 'package:warranty_cave/presentation/app_controller.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('iOS native startup, guest warranty persistence and navigation', (
    tester,
  ) async {
    expect(Platform.isIOS, isTrue);
    await application.main();
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(application.WarrantyCaveApp).evaluate().isNotEmpty) break;
    }
    final context = tester.element(find.byType(application.WarrantyCaveApp));
    final app = context.read<AppController>();
    for (
      var i = 0;
      i < 50 && (app.loading || !app.deferredServicesReady);
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(app.loadError, isNull);
    expect(app.deferredServicesReady, isTrue);
    expect(app.signedIn, isFalse);
    expect(app.accountEnabled, isFalse);
    expect(app.settings.notificationConsentGranted, isFalse);
    await app.completeOnboarding();
    final item = WarrantyItem(
      id: 'ios-smoke-warranty',
      productType: 'Other',
      productName: 'iOS test warranty',
      brand: 'Test',
      model: 'Simulator',
      purchaseDate: DateTime(2026, 10, 21),
      expiryDate: DateTime(2027, 10, 21),
      durationLabel: '1 year',
      createdAt: DateTime.now(),
    );
    await app.upsert(item);
    final persisted = await app.storage.load();
    expect(persisted.$1.any((entry) => entry.id == item.id), isTrue);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('WarrantyCave'), findsWidgets);
    await tester.tap(find.byIcon(Icons.inventory_2_outlined).last);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text(item.productName), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
