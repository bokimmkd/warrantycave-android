import 'dart:async';
import 'dart:io';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import '../domain/models.dart';
import 'services.dart';

class PlayBillingProducts {
  static const basicYearly = 'warrantycave_basic_yearly';
  static const plusYearly = 'warrantycave_plus_yearly';
  static const ids = <String>{basicYearly, plusYearly};

  static PlanTier? tierFor(String productId) => switch (productId) {
    basicYearly => PlanTier.basic,
    plusYearly => PlanTier.plus,
    _ => null,
  };
}

class GooglePlaySubscriptionService implements SubscriptionService {
  GooglePlaySubscriptionService({InAppPurchase? store})
    : _store = store ?? InAppPurchase.instance;

  final InAppPurchase _store;
  final _updates = StreamController<BillingUpdate>.broadcast();
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  final Map<PlanTier, ProductDetails> _products = {};
  final Map<String, PurchaseDetails> _pendingCompletion = {};
  bool _initialized = false;
  bool _available = false;
  String? _setupError;

  @override
  Stream<BillingUpdate> get updates => _updates.stream;

  @override
  bool get isAvailable => _available && _products.length == 2;

  @override
  String? get setupError => _setupError;

  @override
  String priceFor(PlanTier tier) => _products[tier]?.price ?? switch (tier) {
    PlanTier.basic => '\$2.99 / year',
    PlanTier.plus => '\$5.99 / year',
    PlanTier.free => '\$0 forever',
  };

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _purchaseSubscription = _store.purchaseStream.listen(
      _handlePurchases,
      onError: (Object error) => _updates.add(
        BillingUpdate(
          status: BillingUpdateStatus.error,
          error: error.toString(),
        ),
      ),
    );
    try {
      _available = await _store.isAvailable();
      if (!_available) {
        _setupError = 'Google Play Billing is unavailable on this device.';
        return;
      }
      final response = await _store.queryProductDetails(
        PlayBillingProducts.ids,
      );
      if (response.error != null) {
        _setupError = response.error!.message;
      }
      for (final product in response.productDetails) {
        final tier = PlayBillingProducts.tierFor(product.id);
        if (tier != null) _products[tier] = product;
      }
      if (_products.length != 2) {
        _setupError = 'The Google Play subscription products are not active yet.';
      }
    } catch (error) {
      _setupError = error.toString();
    }
  }

  @override
  Future<bool> purchase(PlanTier tier) async {
    await initialize();
    final product = _products[tier];
    if (!_available || product == null) return false;
    final launched = await _store.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
    );
    if (launched) {
      // Some Play Store versions occasionally fail to replay the purchase on
      // purchaseStream after returning to the app. Querying owned purchases is
      // a safe recovery path and gives us the token in time to acknowledge it.
      unawaited(_recoverAndroidPurchasesAfterCheckout());
    }
    return launched;
  }

  @override
  Future<void> restorePurchases() async {
    await initialize();
    if (!_available) {
      _updates.add(
        BillingUpdate(
          status: BillingUpdateStatus.error,
          error: _setupError ?? 'Google Play Billing is unavailable.',
        ),
      );
      return;
    }
    if (Platform.isAndroid) {
      await _queryAndroidPurchases().timeout(const Duration(seconds: 15));
      return;
    }
    await _store.restorePurchases().timeout(const Duration(seconds: 15));
  }

  Future<void> _recoverAndroidPurchasesAfterCheckout() async {
    if (!Platform.isAndroid) return;
    // Give the Play purchase sheet time to close and persist the transaction.
    await Future<void>.delayed(const Duration(seconds: 2));
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final found = await _queryAndroidPurchases();
        if (found) return;
      } catch (_) {
        // The normal purchase stream can still complete the transaction. A
        // later retry below covers short BillingClient reconnects.
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
  }

  Future<bool> _queryAndroidPurchases() async {
    final android = _store
        .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
    final response = await android.queryPastPurchases();
    if (response.error != null) {
      throw StateError(response.error!.message);
    }
    final purchases = response.pastPurchases
        .where(
          (purchase) =>
              PlayBillingProducts.ids.contains(purchase.productID),
        )
        .toList(growable: false);
    if (purchases.isNotEmpty) await _handlePurchases(purchases);
    return purchases.isNotEmpty;
  }

  Future<void> _handlePurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      final tier = PlayBillingProducts.tierFor(purchase.productID);
      if (tier == null) continue;
      if (purchase.status == PurchaseStatus.pending) {
        _updates.add(
          BillingUpdate(
            status: BillingUpdateStatus.pending,
            plan: tier,
            productId: purchase.productID,
          ),
        );
        continue;
      }
      if (purchase.status == PurchaseStatus.error) {
        _updates.add(
          BillingUpdate(
            status: BillingUpdateStatus.error,
            plan: tier,
            productId: purchase.productID,
            error: purchase.error?.message ?? 'Purchase failed.',
          ),
        );
        continue;
      }
      if (purchase.status == PurchaseStatus.canceled) {
        _updates.add(
          BillingUpdate(
            status: BillingUpdateStatus.canceled,
            plan: tier,
            productId: purchase.productID,
          ),
        );
        continue;
      }
      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        final purchaseToken = purchase.verificationData.serverVerificationData;
        if (purchase.pendingCompletePurchase && purchaseToken.isNotEmpty) {
          _pendingCompletion[purchaseToken] = purchase;
        }
        _updates.add(
          BillingUpdate(
            status: purchase.status == PurchaseStatus.restored
                ? BillingUpdateStatus.restored
                : BillingUpdateStatus.purchased,
            plan: tier,
            productId: purchase.productID,
            purchaseToken: purchaseToken,
          ),
        );
      }
    }
  }

  @override
  Future<void> completePurchase(String purchaseToken) async {
    final purchase = _pendingCompletion.remove(purchaseToken);
    if (purchase != null && purchase.pendingCompletePurchase) {
      await _store.completePurchase(purchase);
    }
  }

  @override
  bool canAddItem(PlanTier tier, int currentCount) =>
      currentCount < tier.itemLimit;

  @override
  Future<void> dispose() async {
    await _purchaseSubscription?.cancel();
    await _updates.close();
  }
}
