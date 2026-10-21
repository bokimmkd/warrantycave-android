import 'dart:async';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import '../domain/models.dart';
import 'play_billing_service.dart' show PlayBillingProducts;
import 'services.dart';

class AppleSubscriptionService implements SubscriptionService {
  AppleSubscriptionService({
    required this.accountToken,
    InAppPurchase? store,
    this.enabled = const bool.fromEnvironment('IOS_APPLE_BILLING_ENABLED'),
  }) : _store = store ?? InAppPurchase.instance;

  final Future<String> Function() accountToken;
  final InAppPurchase _store;
  final bool enabled;
  final _updates = StreamController<BillingUpdate>.broadcast();
  final _products = <PlanTier, ProductDetails>{};
  final _pending = <String, PurchaseDetails>{};
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  Future<void>? _initialization;
  bool _available = false;
  String? _error;

  @override
  Stream<BillingUpdate> get updates => _updates.stream;
  @override
  bool get isAvailable => _available && _products.length == 2;
  @override
  String? get setupError => _error;
  @override
  String priceFor(PlanTier tier) => _products[tier]?.price ?? '—';

  @override
  Future<void> initialize() => _initialization ??= _initialize();
  Future<void> _initialize() async {
    if (!enabled) {
      _error = 'App Store subscriptions are not available yet.';
      return;
    }
    _subscription = _store.purchaseStream.listen(
      _handlePurchases,
      onError: (Object error) => _emitError(error.toString()),
    );
    try {
      _available = await _store.isAvailable();
      if (!_available) {
        _error = 'The App Store is unavailable.';
        return;
      }
      final response = await _store.queryProductDetails(
        PlayBillingProducts.ids,
      );
      for (final product in response.productDetails) {
        final tier = PlayBillingProducts.tierFor(product.id);
        if (tier != null) _products[tier] = product;
      }
      if (!isAvailable)
        _error =
            response.error?.message ??
            'App Store subscriptions are not available yet.';
    } catch (error) {
      _error = error.toString();
    }
  }

  @override
  Future<bool> purchase(
    PlanTier tier, {
    PlanTier currentPlan = PlanTier.free,
  }) async {
    await initialize();
    final product = _products[tier];
    if (!isAvailable || product == null) return false;
    // The server-issued UUID binds this StoreKit transaction to the signed-in
    // Firebase user; it contains no email address or other personal data.
    final token = await accountToken();
    return _store.buyNonConsumable(
      purchaseParam: Sk2PurchaseParam(
        productDetails: product,
        applicationUserName: token,
      ),
    );
  }

  @override
  Future<void> restorePurchases() async {
    await initialize();
    if (!enabled || !_available)
      throw StateError(_error ?? 'The App Store is unavailable.');
    await _store.restorePurchases(applicationUserName: await accountToken());
  }

  void _emitError(String message) => _updates.add(
    BillingUpdate(
      status: BillingUpdateStatus.error,
      store: BillingStore.appStore,
      error: message,
    ),
  );

  void _handlePurchases(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      final tier = PlayBillingProducts.tierFor(purchase.productID);
      if (tier == null) continue;
      final id = purchase.purchaseID;
      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        if (purchase is! SK2PurchaseDetails ||
            id == null ||
            purchase.verificationData.serverVerificationData.isEmpty) {
          _emitError(
            'The App Store did not return verifiable transaction details.',
          );
          continue;
        }
        if (purchase.pendingCompletePurchase) _pending[id] = purchase;
      }
      _updates.add(
        BillingUpdate(
          store: BillingStore.appStore,
          status: switch (purchase.status) {
            PurchaseStatus.pending => BillingUpdateStatus.pending,
            PurchaseStatus.purchased => BillingUpdateStatus.purchased,
            PurchaseStatus.restored => BillingUpdateStatus.restored,
            PurchaseStatus.canceled => BillingUpdateStatus.canceled,
            PurchaseStatus.error => BillingUpdateStatus.error,
          },
          plan: tier,
          productId: purchase.productID,
          purchaseToken: id,
          signedTransaction: purchase.verificationData.serverVerificationData,
          error: purchase.error?.message,
        ),
      );
    }
  }

  @override
  Future<void> completePurchase(String purchaseToken) async {
    final purchase = _pending[purchaseToken];
    if (purchase == null) return;
    await _store.completePurchase(purchase);
    _pending.remove(purchaseToken);
  }

  @override
  bool canAddItem(PlanTier tier, int currentCount) =>
      currentCount < tier.itemLimit;
  @override
  Future<void> dispose() async {
    await _subscription?.cancel();
    await _updates.close();
  }
}
