import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:warranty_cave/data/account_local_store.dart';
import 'package:warranty_cave/data/firebase_services.dart';
import 'package:warranty_cave/domain/models.dart';

WarrantyItem item(String id) => WarrantyItem(id: id, productType: 'Phone',
  productName: id, purchaseDate: DateTime(2026), expiryDate: DateTime(2028),
  durationLabel: '2 years', createdAt: DateTime(2026));

void main() {
  late Directory dir;
  late AccountLocalStore store;
  setUp(() async { dir = await Directory.systemTemp.createTemp('wc-accounts-'); store = AccountLocalStore(directory: dir); });
  tearDown(() async { await dir.delete(recursive: true); });
  Future<void> legacy(AppSettings settings) async {
    final file = File('${dir.path}/warrantycave/data.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode({'schemaVersion': 2,
      'items': [item('old').toJson()], 'settings': settings.toJson()}));
  }
  test('existing paid account survives upgrade, sign-out and restart', () async {
    await legacy(const AppSettings(plan: PlanTier.plus, email: 'a@test.com',
      cloudOwnerUid: 'A', onboardingComplete: true));
    final a = await store.activate('A', email: 'a@test.com');
    expect(a.$1.single.id, 'old'); expect(a.$2.plan, PlanTier.plus);
    final guest = await store.activate(null);
    expect(guest.$1, isEmpty); expect(guest.$2.plan, PlanTier.free);
    expect(guest.$2.email, isEmpty); expect(guest.$2.onboardingComplete, isTrue);
    store = AccountLocalStore(directory: dir);
    final again = await store.activate('A', email: 'a@test.com');
    expect(again.$1.single.id, 'old'); expect(again.$2.plan, PlanTier.plus);
  });
  test('signed-out legacy Free data waits for its own account', () async {
    await legacy(const AppSettings(email: 'a@test.com'));
    expect((await store.activate(null)).$1, isEmpty);
    expect((await store.activate('B', email: 'b@test.com')).$1, isEmpty);
    final a = await store.activate('A', email: 'A@test.com');
    expect(a.$1.single.id, 'old'); expect(a.$2.plan, PlanTier.free);
  });
  test('active legacy Free account with no email retains local records', () async {
    await legacy(const AppSettings());
    expect((await store.activate('A', email: 'a@test.com')).$1.single.id, 'old');
  });
  test('guest transfers once, account switching never inherits another vault', () async {
    await store.activate('A');
    await store.save([item('account')], const AppSettings(plan: PlanTier.basic));
    await store.activate(null);
    await store.save([item('guest')], const AppSettings(onboardingComplete: true));
    final a = await store.activate('A', claimGuest: true);
    expect(a.$1.map((e) => e.id), unorderedEquals(['guest','account']));
    expect(a.$2.plan, PlanTier.basic);
    expect((await store.activate(null)).$1, isEmpty);
    expect((await store.activate('B', claimGuest: true)).$1, isEmpty);
    expect((await store.activate('A', claimGuest: true)).$1.length, 2);
  });
  test('startup does not silently claim a guest vault', () async {
    await store.activate(null); await store.save([item('guest')], const AppSettings());
    expect((await store.activate('A')).$1, isEmpty);
    expect((await store.activate(null)).$1.single.id, 'guest');
  });
  test('concurrent disk operations preserve both owners', () async {
    await store.activate('A');
    final saving = store.save([item('A')], const AppSettings());
    final switching = store.activate('B');
    await saving; await switching;
    await store.save([item('B')], const AppSettings());
    expect((await store.activate('A')).$1.single.id, 'A');
    expect((await store.activate('B')).$1.single.id, 'B');
  });
  test('corrupt primary recovers backup without replacing it with invalid data', () async {
    await store.activate('A'); await store.save([item('safe')], const AppSettings());
    await store.activate(null);
    final primary = File('${dir.path}/warrantycave/data.json');
    await primary.writeAsString('{"schemaVersion":3,"profiles":42}');
    expect((await store.activate('A')).$1.single.id, 'safe');
    await primary.writeAsString('broken');
    expect((await store.activate('A')).$1.single.id, 'safe');
  });
  test('unrecoverable data fails closed and leaves original file intact', () async {
    final file = File('${dir.path}/warrantycave/data.json');
    await file.parent.create(recursive: true); await file.writeAsString('broken');
    await expectLater(store.activate(null), throwsFormatException);
    expect(await file.readAsString(), 'broken');
  });
  test('deleting an account preserves other accounts and removes backup copy', () async {
    await store.activate('A'); await store.save([item('private-A')], const AppSettings());
    await store.activate('B'); await store.save([item('B')], const AppSettings());
    await store.removeAccount('A');
    expect((await store.activate('B')).$1.single.id, 'B');
    expect(await File('${dir.path}/warrantycave/data.json.bak').readAsString(), isNot(contains('private-A')));
    expect((await store.activate('A')).$1, isEmpty);
  });
  test('cloud merge retains guest and remote items, deduplicates and honors deletions', () {
    final merged = mergeAccountWarranties([item('guest'), item('same')],
      [item('remote'), item('same'), item('deleted')], ['deleted']);
    expect(merged.map((e) => e.id), unorderedEquals(['guest','remote','same']));
  });
}
