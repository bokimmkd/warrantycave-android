import 'dart:async';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../data/firebase_services.dart';
import '../data/services.dart';
import '../domain/models.dart';

class AppController extends ChangeNotifier {
  static const _plusTestAccounts = {'bokimk.ap@gmail.com'};

  AppController({
    required this.storage,
    required this.photos,
    required this.notifications,
    required this.subscriptions,
    this.accounts,
    this.cloud,
  });

  final LocalStorageService storage;
  final PhotoStorageService photos;
  final NotificationService notifications;
  final SubscriptionService subscriptions;
  final FirebaseAccountService? accounts;
  final FirebaseCloudService? cloud;
  final _uuid = const Uuid();

  List<WarrantyItem> items = [];
  AppSettings settings = const AppSettings();
  bool loading = true;
  bool cloudSyncing = false;
  DateTime? lastCloudSync;
  String? loadError;
  String? cloudError;
  bool smartScanBusy = false;
  bool billingBusy = false;
  bool billingAvailable = false;
  String? billingError;
  StreamSubscription<BillingUpdate>? _billingSubscription;

  User? get user => accounts?.currentUser;
  bool get accountEnabled => accounts != null && cloud != null;
  bool get signedIn => user != null;
  bool get emailVerified => user?.emailVerified ?? false;
  bool get usesPassword => accounts?.usesPassword ?? false;
  String get accountEmail => user?.email ?? settings.email;

  bool get _isPlusTester =>
      _plusTestAccounts.contains((user?.email ?? '').trim().toLowerCase());

  Future<void> initialize() async {
    try {
      final loaded = await storage.load();
      items = loaded.$1;
      settings = loaded.$2;
      _billingSubscription ??= subscriptions.updates.listen(
        _handleBillingUpdate,
      );
      await subscriptions.initialize();
      billingAvailable = subscriptions.isAvailable;
      billingError = subscriptions.setupError;
      if (signedIn && emailVerified) await _syncForUser();
      await subscriptions.restorePurchases();
      await notifications.initialize();
      for (final item in items) {
        await notifications.scheduleFor(item, settings);
      }
    } catch (error) {
      loadError = error.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  bool get canAdd => subscriptions.canAddItem(settings.plan, items.length);
  String billingPrice(PlanTier tier) => subscriptions.priceFor(tier);
  String newId() => _uuid.v4();

  Future<void> purchasePlan(PlanTier tier) async {
    if (tier == PlanTier.free) return;
    if (!signedIn || !emailVerified || cloud == null) {
      throw StateError('verified-account-required');
    }
    billingError = null;
    billingBusy = true;
    notifyListeners();
    final launched = await subscriptions.purchase(tier);
    if (!launched) {
      billingBusy = false;
      billingError =
          subscriptions.setupError ?? 'Google Play Billing is unavailable.';
      notifyListeners();
      throw StateError(billingError!);
    }
  }

  Future<void> restorePurchases() async {
    billingError = null;
    billingBusy = true;
    notifyListeners();
    try {
      await subscriptions.restorePurchases();
    } finally {
      // Google Play sends restored purchases through the update stream, but it
      // sends no event when there is nothing to restore. Always release the UI.
      billingBusy = false;
      notifyListeners();
    }
  }

  Future<void> _handleBillingUpdate(BillingUpdate update) async {
    if (update.status == BillingUpdateStatus.pending) {
      billingBusy = true;
      billingError = null;
      notifyListeners();
      return;
    }
    if (update.status == BillingUpdateStatus.canceled) {
      billingBusy = false;
      notifyListeners();
      return;
    }
    if (update.status == BillingUpdateStatus.error) {
      billingBusy = false;
      billingError = update.error ?? 'Google Play purchase failed.';
      notifyListeners();
      return;
    }
    final token = update.purchaseToken;
    final productId = update.productId;
    if (!signedIn || !emailVerified || cloud == null) {
      billingBusy = false;
      billingError = 'Sign in with a verified account to restore this plan.';
      notifyListeners();
      return;
    }
    if (token == null || token.isEmpty || productId == null) {
      billingBusy = false;
      billingError = 'Google Play did not return a valid purchase token.';
      notifyListeners();
      return;
    }
    try {
      final entitlement = await cloud!.confirmPlayPurchase(
        productId: productId,
        purchaseToken: token,
      );
      await subscriptions.completePurchase(token);
      settings = settings.copyWith(
        plan: _isPlusTester ? PlanTier.plus : entitlement.plan,
        planExpiresAt: entitlement.expiresAt,
        clearPlanExpiry: entitlement.expiresAt == null,
      );
      await storage.save(items, settings);
      billingError = null;
      if (settings.plan.hasCloud) await _syncForUser();
    } catch (error) {
      billingError = error.toString();
    } finally {
      billingBusy = false;
      notifyListeners();
    }
  }

  Future<void> upsert(WarrantyItem item) async {
    final index = items.indexWhere((entry) => entry.id == item.id);
    final removedPhotos = <String>[];
    if (index < 0) {
      if (!canAdd) throw StateError('plan_limit');
      items = [...items, item];
    } else {
      final previous = items[index];
      removedPhotos.addAll(
        [
          if (previous.productPhoto != null) previous.productPhoto!,
          ...previous.receiptPhotos,
          ...previous.warrantyPhotos,
        ].where(
          (path) => ![
            if (item.productPhoto != null) item.productPhoto!,
            ...item.receiptPhotos,
            ...item.warrantyPhotos,
          ].contains(path),
        ),
      );
      items = [...items]..[index] = item;
    }
    await _persist();
    for (final path in removedPhotos) await photos.delete(path);
    await notifications.scheduleFor(item, settings);
    await _cloudAction(() => cloud!.saveItem(user!.uid, item));
  }

  Future<void> delete(WarrantyItem item) async {
    items = items.where((entry) => entry.id != item.id).toList();
    await notifications.cancelFor(item.id);
    for (final path in [
      if (item.productPhoto != null) item.productPhoto!,
      ...item.receiptPhotos,
      ...item.warrantyPhotos,
    ])
      await photos.delete(path);
    await _persist();
    await _cloudAction(() => cloud!.deleteItem(user!.uid, item.id));
  }

  Future<String?> addPhoto({
    required String itemId,
    required String kind,
    required ImageSource source,
  }) => photos.capture(source, itemId, kind);

  Future<void> updateSettings(AppSettings value) async {
    settings = value;
    await _persist();
    for (final item in items) await notifications.scheduleFor(item, settings);
    await _cloudAction(() => cloud!.saveProfile(user!.uid, settings));
  }

  Future<void> createAccount({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    String referralCode = '',
  }) async {
    final normalizedReferral = ReferralPolicy.normalize(referralCode);
    if (normalizedReferral.isNotEmpty &&
        !ReferralPolicy.isValid(normalizedReferral)) {
      throw const FormatException('invalid-referral-code');
    }
    await accounts!.createAccount(
      email: email.trim(),
      password: password,
      displayName: '$firstName $lastName'.trim(),
    );
    final ownReferralCode = ReferralPolicy.codeForUser(user!.uid);
    settings = settings.copyWith(
      firstName: firstName.trim(),
      lastName: lastName.trim(),
      email: email.trim(),
      referralCode: ownReferralCode,
      pendingReferralCode: normalizedReferral,
    );
    await _persist();
    await cloud?.registerReferralSignup(
      uid: user!.uid,
      ownCode: ownReferralCode,
      invitedByCode: normalizedReferral,
      email: email.trim(),
    );
  }

  Future<void> signIn(String email, String password) async {
    await accounts!.signIn(email.trim(), password);
    if (emailVerified) await _syncForUser();
    notifyListeners();
  }

  Future<void> signInWithGoogle() async {
    await accounts!.signInWithGoogle();
    final name = (user?.displayName ?? '').trim();
    final parts = name.isEmpty ? <String>[] : name.split(RegExp(r'\s+'));
    settings = settings.copyWith(
      firstName: parts.isEmpty ? settings.firstName : parts.first,
      lastName: parts.length < 2 ? settings.lastName : parts.skip(1).join(' '),
      email: user?.email ?? settings.email,
    );
    await _syncForUser();
    notifyListeners();
  }

  Future<void> sendPasswordReset(String email) =>
      accounts!.resetPassword(email.trim());
  Future<void> resendVerification() => accounts!.resendVerification();

  Future<bool> checkVerification() async {
    final verified = await accounts!.reloadVerification();
    if (verified) await _syncForUser();
    notifyListeners();
    return verified;
  }

  Future<void> signOut() async {
    await accounts!.signOut();
    notifyListeners();
  }

  Future<void> deleteAccount({String? password}) async {
    final uid = user!.uid;
    await accounts!.reauthenticate(password: password);
    await cloud!.deleteUserData(uid);
    await accounts!.deleteCurrentUser();
    for (final item in items) {
      for (final path in [
        if (item.productPhoto != null) item.productPhoto!,
        ...item.receiptPhotos,
        ...item.warrantyPhotos,
      ])
        await photos.delete(path);
    }
    items = [];
    settings = AppSettings(onboardingComplete: settings.onboardingComplete);
    await _persist();
  }

  Future<bool> requestNotificationPermission() async {
    final granted = await notifications.requestPermission();
    if (granted) {
      settings = settings.copyWith(notificationConsentGranted: true);
      await _persist();
      for (final item in items) {
        await notifications.scheduleFor(item, settings);
      }
    }
    return granted;
  }
  Future<void> completeOnboarding() =>
      updateSettings(settings.copyWith(onboardingComplete: true));

  Future<void> _syncForUser() async {
    if (!signedIn || !emailVerified || cloud == null) return;
    if (settings.referralCode.isEmpty) {
      final ownCode = ReferralPolicy.codeForUser(user!.uid);
      settings = settings.copyWith(referralCode: ownCode);
      await storage.save(items, settings);
      await cloud!.registerReferralSignup(
        uid: user!.uid,
        ownCode: ownCode,
        invitedByCode: settings.pendingReferralCode,
        email: user?.email ?? settings.email,
      );
    }
    try {
      final entitlement = await cloud!.getEntitlements();
      settings = settings.copyWith(
        plan: _isPlusTester ? PlanTier.plus : entitlement.plan,
        smartScanCredits: entitlement.smartScanCredits,
        planExpiresAt: entitlement.expiresAt,
        clearPlanExpiry: entitlement.expiresAt == null,
      );
      await storage.save(items, settings);
    } catch (error) {
      if (_isPlusTester) {
        settings = settings.copyWith(
          plan: PlanTier.plus,
          smartScanCredits: 999,
        );
        await storage.save(items, settings);
      } else {
        cloudError = error.toString();
      }
    }
    if (!settings.plan.hasCloud) {
      notifyListeners();
      return;
    }
    cloudSyncing = true;
    cloudError = null;
    notifyListeners();
    try {
      settings = settings.copyWith(email: user?.email ?? settings.email);
      final result = await cloud!.bootstrap(user!.uid, items, settings);
      items = result.items;
      settings = result.settings.copyWith(
        email: user?.email ?? settings.email,
        plan: _isPlusTester ? PlanTier.plus : result.settings.plan,
      );
      await storage.save(items, settings);
      lastCloudSync = DateTime.now();
    } catch (error) {
      cloudError = error.toString();
    } finally {
      cloudSyncing = false;
      notifyListeners();
    }
  }

  Future<void> refreshCloud() async {
    if (!signedIn || !emailVerified || cloud == null) return;
    if (!settings.plan.hasCloud) {
      cloudError = 'Cloud sync is available on Basic and Plus plans.';
      notifyListeners();
      return;
    }
    if (cloudSyncing) return;
    cloudSyncing = true;
    cloudError = null;
    notifyListeners();
    try {
      final entitlement = await cloud!.getEntitlements();
      settings = settings.copyWith(
        plan: _isPlusTester ? PlanTier.plus : entitlement.plan,
        smartScanCredits: entitlement.smartScanCredits,
        planExpiresAt: entitlement.expiresAt,
        clearPlanExpiry: entitlement.expiresAt == null,
      );
      final result = await cloud!.refresh(user!.uid, settings);
      items = result.items;
      settings = result.settings.copyWith(
        email: user?.email ?? settings.email,
        plan: _isPlusTester ? PlanTier.plus : result.settings.plan,
      );
      await storage.save(items, settings);
      for (final item in items) {
        await notifications.scheduleFor(item, settings);
      }
      lastCloudSync = DateTime.now();
    } catch (error) {
      cloudError = error.toString();
    } finally {
      cloudSyncing = false;
      notifyListeners();
    }
  }

  Future<void> redeemFounderCode(String code) async {
    if (!signedIn || !emailVerified || cloud == null) {
      throw StateError('verified-account-required');
    }
    final result = await cloud!.redeemFounderCode(code);
    settings = settings.copyWith(
      plan: result.plan,
      planExpiresAt: result.expiresAt,
    );
    await storage.save(items, settings);
    await _syncForUser();
    notifyListeners();
  }

  Future<ScanSuggestion> smartScanReceipt(String localImagePath) async {
    if (!signedIn || !emailVerified || cloud == null) {
      throw StateError('verified-account-required');
    }
    if (settings.smartScanCredits < 1 && !_isPlusTester) {
      throw StateError('no-scan-credits');
    }
    smartScanBusy = true;
    notifyListeners();
    try {
      final suggestion = await cloud!.smartScanReceipt(localImagePath);
      if (suggestion.remainingCredits != null) {
        settings = settings.copyWith(
          smartScanCredits: suggestion.remainingCredits,
        );
        await storage.save(items, settings);
      }
      return suggestion;
    } finally {
      smartScanBusy = false;
      notifyListeners();
    }
  }

  Future<void> _cloudAction(Future<void> Function() action) async {
    if (!signedIn ||
        !emailVerified ||
        cloud == null ||
        !settings.plan.hasCloud) {
      return;
    }
    try {
      cloudError = null;
      cloudSyncing = true;
      notifyListeners();
      await action();
      lastCloudSync = DateTime.now();
    } catch (error) {
      cloudError = error.toString();
    } finally {
      cloudSyncing = false;
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    await storage.save(items, settings);
    notifyListeners();
  }

  int countFor(WarrantyStatus status) => items
      .where(
        (item) =>
            item.status(thresholdDays: settings.expiringThresholdDays) ==
            status,
      )
      .length;
  bool photoExists(String path) =>
      path.startsWith('https://') || File(path).existsSync();

  @override
  void dispose() {
    final billingSubscription = _billingSubscription;
    if (billingSubscription != null) {
      unawaited(billingSubscription.cancel());
    }
    unawaited(subscriptions.dispose());
    super.dispose();
  }
}
