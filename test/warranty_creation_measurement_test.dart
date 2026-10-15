import 'package:warranty_cave/data/usage_analytics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:warranty_cave/data/services.dart';
import 'package:warranty_cave/domain/models.dart';
import 'package:warranty_cave/presentation/app_controller.dart';

WarrantyItem warranty(int number, PlanTier origin, {DateTime? expiry}) =>
    WarrantyItem(
      id: 'item-$number',
      productType: 'Phone',
      productName: 'Phone $number',
      purchaseDate: DateTime(2026, 1, 1),
      expiryDate: expiry ?? DateTime.now().add(const Duration(days: 120)),
      durationLabel: '1 year',
      createdAt: DateTime(2026, 1, 1),
      createdOnPlan: origin,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('successful local create counts once; edits/imports/retries are deduplicated', () async {
    final analytics = _Analytics();
    final storage = _MemoryStorage([
      warranty(8, PlanTier.free),
    ], const AppSettings());
    final app = AppController(
      storage: storage,
      photos: _NoopPhotos(),
      notifications: _NoopNotifications(),
      subscriptions: LocalSubscriptionService(),
      analytics: analytics,
    );
    await app.initialize();
    await app.upsert(warranty(8, PlanTier.free));
    expect(analytics.creates, 0);
    await app.upsert(warranty(1, PlanTier.free));
    expect(analytics.creates, 1);
    await app.upsert(warranty(1, PlanTier.free));
    expect(analytics.creates, 1);
    // Simulate a downloaded old record. Its first local edit is not a create.
    app.items = [...app.items, warranty(9, PlanTier.free)];
    await app.upsert(warranty(9, PlanTier.free));
    expect(analytics.creates, 1);
    storage.fail = true;
    await expectLater(app.upsert(warranty(2, PlanTier.free)), throwsStateError);
    expect(analytics.creates, 1);
    storage.fail = false;
    await app.upsert(warranty(2, PlanTier.free));
    expect(analytics.creates, 2);
    await app.upsert(warranty(2, PlanTier.free));
    expect(analytics.creates, 2);
    app.dispose();
  });
}

class _Analytics extends UsageAnalytics {
  int creates = 0;
  @override
  Future<void> warrantyCreated() async {
    creates++;
  }
}

class _MemoryStorage implements LocalStorageService {
  _MemoryStorage(this.items, this.settings);
  List<WarrantyItem> items;
  AppSettings settings;
  bool fail = false;

  @override
  Future<(List<WarrantyItem>, AppSettings)> load() async => (items, settings);

  @override
  Future<void> save(List<WarrantyItem> items, AppSettings settings) async {
    if (fail) throw StateError("disk full");
    this.items = items;
    this.settings = settings;
  }
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
