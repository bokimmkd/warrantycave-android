import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:warranty_cave/data/services.dart';
import 'package:warranty_cave/domain/models.dart';
import 'package:warranty_cave/presentation/app_controller.dart';

WarrantyItem warranty(int number, PlanTier origin, {DateTime? expiry}) => WarrantyItem(
  id: 'item-$number',
  productType: 'Phone',
  productName: 'Phone $number',
  purchaseDate: DateTime(2026, 1, 1),
  expiryDate: expiry ?? DateTime.now().add(const Duration(days: 120)),
  durationLabel: '1 year',
  createdAt: DateTime(2026, 1, 1),
  createdOnPlan: origin,
);

Future<AppController> controllerWith(
  List<WarrantyItem> items,
  PlanTier tier, {
  DateTime? expiresAt,
}) async {
  final controller = AppController(
    storage: _MemoryStorage(
      items,
      AppSettings(plan: tier, planExpiresAt: expiresAt),
    ),
    photos: _NoopPhotos(),
    notifications: _NoopNotifications(),
    subscriptions: LocalSubscriptionService(),
  );
  await controller.initialize();
  return controller;
}

void main() {
  test('expiry day and two following days count, then archive does not', () {
    final today = dateOnly(DateTime.now());
    for (final age in [0, 1, 2]) {
      final item = warranty(1, PlanTier.free,
          expiry: today.subtract(Duration(days: age)));
      expect(item.isArchived(now: today), isFalse);
    }
    final archived = warranty(2, PlanTier.free,
        expiry: today.subtract(const Duration(days: 3)));
    expect(archived.isArchived(now: today), isTrue);
  });

  test('origin survives local and cloud JSON; old records stay editable', () {
    final plus = warranty(1, PlanTier.plus);
    expect(WarrantyItem.fromJson(plus.toJson()).createdOnPlan, PlanTier.plus);
    final legacy = Map<String, dynamic>.from(plus.toJson())
      ..remove('createdOnPlan');
    expect(WarrantyItem.fromJson(legacy).createdOnPlan, PlanTier.free);
  });

  test('pending cloud deletions survive app restart', () {
    final settings = AppSettings(
      cloudOwnerUid: 'original-owner',
      pendingCloudDeletionIds: const ['deleted-while-free'],
    );
    final restored = AppSettings.fromJson(settings.toJson());
    expect(restored.cloudOwnerUid, 'original-owner');
    expect(restored.pendingCloudDeletionIds, ['deleted-while-free']);
    expect(
      restored.copyWith(pendingCloudDeletionIds: []).pendingCloudDeletionIds,
      isEmpty,
    );
  });

  test('26 Plus items remain counted and locked after expiry', () async {
    final app = await controllerWith(
      List.generate(26, (i) => warranty(i, PlanTier.plus)),
      PlanTier.free,
    );
    expect(app.canAdd, isFalse);
    expect(app.canEditItem(app.items.first), isFalse);
    await expectLater(
      app.upsert(warranty(0, PlanTier.plus)),
      throwsA(isA<StateError>()),
    );
    expect(app.items.length, 26);
    expect(await app.delete(app.items.first), isTrue);
    expect(app.items.length, 25);
    expect(app.canAdd, isFalse);
  });

  test('Basic freezes all 26 active warranties, even legacy Free origins', () async {
    final app = await controllerWith(
      List.generate(26, (i) => warranty(i, PlanTier.free)),
      PlanTier.basic,
    );
    expect(app.countedItemCount, 26);
    expect(app.canAdd, isFalse);
    expect(app.items.every((item) => !app.canEditItem(item)), isTrue);
    await expectLater(
      app.upsert(app.items.first), throwsA(isA<StateError>()),
    );
    expect(await app.delete(app.items.last), isTrue);
    expect(app.countedItemCount, 25);
    expect(app.canEditItem(app.items.first), isTrue);
    expect(app.canAdd, isFalse);
  });

  test('archived warranty frees a slot without deleting its Claim Pack data', () async {
    final today = dateOnly(DateTime.now());
    final inGrace = warranty(25, PlanTier.free,
        expiry: today.subtract(const Duration(days: 2)));
    final beforeArchive = await controllerWith(
      [...List.generate(25, (i) => warranty(i, PlanTier.free)), inGrace],
      PlanTier.basic,
    );
    expect(beforeArchive.countedItemCount, 26);
    expect(beforeArchive.canEditItem(beforeArchive.items.first), isFalse);

    final archive = warranty(25, PlanTier.free,
        expiry: today.subtract(const Duration(days: 3)));
    final app = await controllerWith(
      [...List.generate(25, (i) => warranty(i, PlanTier.free)), archive],
      PlanTier.basic,
    );
    expect(app.items.length, 26);
    expect(app.countedItemCount, 25);
    expect(app.canAdd, isFalse);
    expect(app.canEditItem(archive), isFalse);
    expect(app.canEditItem(app.items.first), isTrue);
    await expectLater(app.upsert(archive), throwsA(isA<StateError>()));
    expect(await app.delete(app.items.first), isTrue);
    expect(app.countedItemCount, 24);
    expect(app.canAdd, isTrue);
    await app.upsert(warranty(26, PlanTier.basic));
    expect(app.countedItemCount, 25);
    expect(app.canAdd, isFalse);
  });

  test('nine locked items leave one editable Free slot', () async {
    final app = await controllerWith(
      List.generate(9, (i) => warranty(i, PlanTier.basic)),
      PlanTier.free,
    );
    expect(app.canAdd, isTrue);
    expect(app.canEditItem(app.items.first), isFalse);
    await app.upsert(warranty(9, PlanTier.free));
    expect(app.canEditItem(app.items.last), isTrue);
    expect(app.canAdd, isFalse);
    await expectLater(
      app.upsert(warranty(10, PlanTier.free)),
      throwsA(isA<StateError>()),
    );
    expect(app.items.length, 10);
  });

  test('Basic unlocks Basic items but not Plus items and counts both', () async {
    final app = await controllerWith(
      [warranty(1, PlanTier.free), warranty(2, PlanTier.basic),
       warranty(3, PlanTier.plus)],
      PlanTier.basic,
    );
    expect(app.canEditItem(app.items[0]), isTrue);
    expect(app.canEditItem(app.items[1]), isTrue);
    expect(app.canEditItem(app.items[2]), isFalse);
    app.settings = const AppSettings(plan: PlanTier.plus);
    expect(app.canEditItem(app.items[2]), isTrue);
    app.settings = const AppSettings(plan: PlanTier.free);
    expect(app.canEditItem(app.items[1]), isFalse);
    expect(app.canEditItem(app.items[0]), isTrue);
  });

  test('expired locally cached Plus plan cannot edit or add past Free limit', () async {
    final app = await controllerWith(
      List.generate(11, (i) => warranty(i, PlanTier.plus)),
      PlanTier.plus,
      expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
    );
    expect(app.effectivePlan, PlanTier.free);
    expect(app.canEditItem(app.items.first), isFalse);
    expect(app.canAdd, isFalse);
  });

  test('an edit cannot lower a warranty original plan', () async {
    final app = await controllerWith([warranty(1, PlanTier.plus)], PlanTier.plus);
    await expectLater(
      app.upsert(warranty(1, PlanTier.free)),
      throwsA(isA<StateError>()),
    );
    expect(app.items.single.createdOnPlan, PlanTier.plus);
  });
}

class _MemoryStorage implements LocalStorageService {
  _MemoryStorage(this.items, this.settings);
  List<WarrantyItem> items;
  AppSettings settings;

  @override
  Future<(List<WarrantyItem>, AppSettings)> load() async => (items, settings);

  @override
  Future<void> save(List<WarrantyItem> items, AppSettings settings) async {
    this.items = items;
    this.settings = settings;
  }
}

class _NoopPhotos implements PhotoStorageService {
  @override
  Future<String?> capture(ImageSource source, String itemId, String kind) async => null;
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
