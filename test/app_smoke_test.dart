import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:warranty_cave/data/services.dart';
import 'package:warranty_cave/domain/models.dart';
import 'package:warranty_cave/main.dart';
import 'package:warranty_cave/presentation/app_controller.dart';

void main() {
  testWidgets('cold start renders the branded main shell', (tester) async {
    final controller = AppController(
      storage: _MemoryStorage(),
      photos: _NoopPhotos(),
      notifications: _NoopNotifications(),
      subscriptions: LocalSubscriptionService(),
    );
    await controller.initialize();

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
    expect(find.text('Add'), findsOneWidget);
    expect(find.text('Reminders'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
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
