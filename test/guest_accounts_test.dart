import 'dart:async';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warranty_cave/data/firebase_services.dart';
import 'package:warranty_cave/data/services.dart';
import 'package:warranty_cave/domain/models.dart';
import 'package:warranty_cave/presentation/app_controller.dart';
import 'account_local_store_test.dart' show item;

class TestUser extends Fake implements User {
  TestUser(this.uid, {this.emailVerified = true});
  @override final String uid;
  @override final bool emailVerified;
  @override String get email => '$uid@test.com';
}
class Accounts extends Fake implements FirebaseAccountService {
  @override User? currentUser;
  bool failLogin = false;
  @override bool get usesPassword => true;
  @override Future<User> signIn(String email, String password) async {
    if (failLogin) throw StateError('offline');
    return currentUser = TestUser(email.split('@').first);
  }
  @override Future<void> signOut() async { currentUser = null; }
}
class Cloud extends Fake implements FirebaseCloudService {
  PlanTier plan = PlanTier.basic;
  bool offline = false;
  Completer<void>? gate;
  @override Future<void> registerReferralSignup({required String uid,
    required String ownCode, required String invitedByCode, required String email}) async {}
  @override Future<EntitlementResult> getEntitlements() async {
    await gate?.future;
    if (offline) throw StateError('offline');
    return EntitlementResult(plan: plan, smartScanCredits: 0);
  }
  @override Future<CloudBootstrapResult> bootstrap(String uid, List<WarrantyItem> local, AppSettings settings) async {
    if (offline) throw StateError('offline');
    return CloudBootstrapResult(mergeAccountWarranties(local, [item('cloud-$uid')], []), settings);
  }
}
class Notifications extends Fake implements NotificationService {
  final scheduled = <String>{};
  @override Future<void> initialize() async {}
  @override Future<void> cancelFor(String id) async { scheduled.remove(id); }
  @override Future<void> scheduleFor(WarrantyItem item, AppSettings settings) async { scheduled.add(item.id); }
}
class Photos extends Fake implements PhotoStorageService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late JsonLocalStorageService store;
  late Accounts accounts;
  late Cloud cloud;
  late Notifications notifications;
  late AppController app;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('wc-guest-controller-');
    store = JsonLocalStorageService(directory: dir);
    accounts = Accounts(); cloud = Cloud(); notifications = Notifications();
    app = AppController(storage: store, accounts: accounts, cloud: cloud,
      notifications: notifications, photos: Photos(), subscriptions: LocalSubscriptionService());
    await app.initialize();
    while (!app.deferredServicesReady) { await Future<void>.delayed(Duration.zero); }
  });
  tearDown(() async { app.dispose(); await dir.delete(recursive: true); });
  test('guest uses Free, existing Basic login restores cloud and merges guest records', () async {
    expect(app.effectivePlan, PlanTier.free);
    await app.upsert(item('guest'));
    await app.signIn('A@test.com', 'password');
    expect(app.effectivePlan, PlanTier.basic);
    expect(app.items.map((e) => e.id), unorderedEquals(['guest','cloud-A']));
    await app.signOut();
    expect(app.items, isEmpty); expect(app.effectivePlan, PlanTier.free);
    expect(notifications.scheduled, isEmpty);
    await app.signIn('B@test.com', 'password');
    expect(app.items.single.id, 'cloud-B');
    await app.signOut();
    await app.signIn('A@test.com', 'password');
    expect(app.items.map((e) => e.id), unorderedEquals(['guest','cloud-A']));
  });
  test('old Free accounts keep local data after logout/login without cloud', () async {
    cloud.plan = PlanTier.free;
    await app.signIn('A@test.com', 'password'); await app.upsert(item('free-A'));
    await app.signOut(); expect(app.items, isEmpty);
    await app.signIn('A@test.com', 'password');
    expect(app.items.single.id, 'free-A'); expect(app.effectivePlan, PlanTier.free);
  });
  test('failed login does not transfer or hide guest data', () async {
    await app.upsert(item('guest')); accounts.failLogin = true;
    await expectLater(app.signIn('A@test.com','wrong'), throwsStateError);
    expect(app.signedIn, isFalse); expect(app.items.single.id, 'guest');
    expect(app.accountBusy, isFalse);
  });
  test('existing paid account keeps cache when cloud is temporarily offline', () async {
    cloud.plan = PlanTier.plus;
    await app.signIn('A@test.com','password'); await app.signOut();
    cloud.offline = true;
    await app.signIn('A@test.com','password');
    expect(app.effectivePlan, PlanTier.plus);
    expect(app.items.single.id, 'cloud-A'); expect(app.cloudError, isNotNull);
  });
  test('account switch is blocked while entitlement and cloud loading are in progress', () async {
    cloud.gate = Completer<void>();
    final login = app.signIn('A@test.com','password');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(app.loginStatusKey, 'authCloud');
    await expectLater(app.signOut(), throwsStateError);
    cloud.gate!.complete(); await login;
    expect(app.user!.uid, 'A'); expect(app.effectivePlan, PlanTier.basic);
    expect(app.loginStatusKey, isNull);
  });
  test('purchase and restore require a verified account', () async {
    await expectLater(app.purchasePlan(PlanTier.basic), throwsStateError);
    await expectLater(app.restorePurchases(), throwsStateError);
    accounts.currentUser = TestUser('A', emailVerified: false);
    expect(app.effectivePlan, PlanTier.free);
    await expectLater(app.purchasePlan(PlanTier.plus), throwsStateError);
  });
}
