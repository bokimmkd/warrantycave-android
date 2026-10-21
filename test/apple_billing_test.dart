import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:warranty_cave/data/apple_billing_service.dart';
import 'package:warranty_cave/data/services.dart';
import 'package:warranty_cave/domain/models.dart';

void main() {
  test('Apple checkout stays disabled until explicitly configured', () async {
    final store = _Store();
    final service = AppleSubscriptionService(
      store: store,
      enabled: false,
      accountToken: () async => throw StateError('must not be called'),
    );
    expect(await service.purchase(PlanTier.basic), isFalse);
    expect(store.calls, isEmpty);
    await service.dispose();
    await store.purchases.close();
  });
  test(
    'Apple purchase binds account, forwards signed data and finishes only after confirmation',
    () async {
      final store = _Store();
      final service = AppleSubscriptionService(
        store: store,
        enabled: true,
        accountToken: () async => '4b293923-b932-450a-bc62-96599c5c3481',
      );
      final updates = <BillingUpdate>[];
      final subscription = service.updates.listen(updates.add);
      await service.initialize();
      expect(service.isAvailable, isTrue);
      expect(service.priceFor(PlanTier.basic), '€2,99');
      expect(await service.purchase(PlanTier.basic), isTrue);
      expect(store.parameter, isA<Sk2PurchaseParam>());
      expect(
        store.parameter!.applicationUserName,
        '4b293923-b932-450a-bc62-96599c5c3481',
      );
      store.purchases.add([
        SK2PurchaseDetails(
          productID: 'warrantycave_basic_yearly',
          purchaseID: '1234',
          verificationData: PurchaseVerificationData(
            localVerificationData: '',
            serverVerificationData: 'apple.signed.transaction',
            source: 'app_store',
          ),
          transactionDate: '1',
          status: PurchaseStatus.purchased,
        ),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(updates.single.store, BillingStore.appStore);
      expect(updates.single.signedTransaction, 'apple.signed.transaction');
      expect(
        store.completed,
        isEmpty,
      ); // Server verification has not completed.
      await service.completePurchase('1234');
      expect(store.completed, ['1234']);
      await service.completePurchase('1234');
      expect(store.completed, ['1234']);
      await service.restorePurchases();
      expect(store.restoreAccount, store.parameter!.applicationUserName);
      await subscription.cancel();
      await service.dispose();
      await store.purchases.close();
    },
  );
  test('Apple cannot start checkout when account binding fails', () async {
    final store = _Store();
    final service = AppleSubscriptionService(
      store: store,
      enabled: true,
      accountToken: () async => throw StateError('account required'),
    );
    await expectLater(service.purchase(PlanTier.plus), throwsStateError);
    expect(store.parameter, isNull);
    await service.dispose();
    await store.purchases.close();
  });
}

class _Store implements InAppPurchase {
  final purchases = StreamController<List<PurchaseDetails>>.broadcast();
  final calls = <String>[];
  final completed = <String?>[];
  PurchaseParam? parameter;
  String? restoreAccount;
  @override
  Stream<List<PurchaseDetails>> get purchaseStream => purchases.stream;
  @override
  Future<bool> isAvailable() async {
    calls.add('available');
    return true;
  }

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async =>
      ProductDetailsResponse(
        productDetails: [
          for (final id in ids)
            ProductDetails(
              id: id,
              title: id,
              description: 'Annual subscription',
              price: '€2,99',
              rawPrice: 2.99,
              currencyCode: 'EUR',
            ),
        ],
        notFoundIDs: [],
      );
  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    parameter = purchaseParam;
    return true;
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    restoreAccount = applicationUserName;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completed.add(purchase.purchaseID);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
