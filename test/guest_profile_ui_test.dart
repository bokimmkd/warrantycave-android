import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:warranty_cave/presentation/screens/auth_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:warranty_cave/data/services.dart';
import 'package:warranty_cave/domain/models.dart';
import 'package:warranty_cave/main.dart';
import 'package:warranty_cave/presentation/app_controller.dart';

void main() {
  for (final dark in [false, true]) {
  testWidgets('guest enters Home and can open and leave Profile login (dark=$dark)', (tester) async {
    final controller = _GuestApp(
      storage: _MemoryStorage(),
      photos: _NoopPhotos(),
      notifications: _NoopNotifications(),
      subscriptions: LocalSubscriptionService(),
    );
    await controller.initialize();
    await controller.updateSettings(controller.settings.copyWith(darkMode: dark));

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const WarrantyCaveApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('WarrantyCave'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Items'), findsOneWidget);
    expect(find.text('Add'), findsNWidgets(2));
    expect(find.text('Reminders'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.byType(AuthScreen), findsNothing);
    await tester.tap(find.text('Settings')); await tester.pumpAndSettle();
    await tester.tap(find.text('Profile').first); await tester.pumpAndSettle();
    expect(find.byType(AuthScreen), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    await tester.tap(find.byType(BackButton)); await tester.pumpAndSettle();
    expect(find.byType(AuthScreen), findsNothing);
    expect(controller.signedIn, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  }
}

class _GuestApp extends AppController {
  _GuestApp({required super.storage, required super.photos,
    required super.notifications, required super.subscriptions});
  @override bool get accountEnabled => true;
}

class _MemoryStorage implements LocalStorageService {
  @override
  Future<(List<WarrantyItem>, AppSettings)> load() async =>
      (<WarrantyItem>[], const AppSettings(onboardingComplete: true));

  @override
  Future<void> save(List<WarrantyItem> items, AppSettings settings) async {}
}

class _NoopPhotos implements PhotoStorageService {
  @override
  Future<String?> capture(
    ImageSource source,
    String itemId,
    String kind,
  ) async => null;

  @override
  Future<void> delete(String path) async {}
}

class _NoopNotifications implements NotificationService {
  @override
  Future<void> cancelFor(String itemId) async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> scheduleFor(WarrantyItem item, AppSettings settings) async {}
}

