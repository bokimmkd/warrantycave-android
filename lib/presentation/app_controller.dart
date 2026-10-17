import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../data/firebase_services.dart';
import '../data/services.dart';
import '../data/account_local_store.dart';
import '../data/usage_analytics.dart';
import '../data/play_review.dart';
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
    this.analytics,
    this.reviews,
  });

  final LocalStorageService storage;
  final PhotoStorageService photos;
  final NotificationService notifications;
  final SubscriptionService subscriptions;
  final FirebaseAccountService? accounts;
  final FirebaseCloudService? cloud;
  final UsageAnalytics? analytics;
  final PlayReview? reviews;
  final Set<String> _committedWarrantyIds = {};
  final Set<String> _pendingCreationIds = {};
  bool deferredServicesReady = false;
  bool _disposed = false;
  final _uuid = const Uuid();

  List<WarrantyItem> items = [];
  AppSettings settings = const AppSettings();
  bool loading = true;
  bool accountBusy = false;
  int _localWrites = 0;
  int _backgroundOperations = 0;
  bool get accountActionBusy => accountBusy || cloudSyncing || billingBusy || smartScanBusy || _localWrites > 0 || _backgroundOperations > 0;

  bool cloudSyncing = false;
  bool _cloudBootstrapPending = true;
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
    loading = true;
    notifyListeners();
    try {
      loadError = null;
      final loaded = storage is AccountLocalStore
          ? await (storage as AccountLocalStore).activate(user?.uid, email: user?.email)
          : await storage.load();
      items = loaded.$1;
      _committedWarrantyIds.addAll(items.map((item) => item.id));
      await reviews?.observe(items.length, existingAccount: signedIn);
      settings = loaded.$2;
      _billingSubscription ??= subscriptions.updates.listen(
        _handleBillingUpdate,
      );
    } catch (error) {
      loadError = error.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
    // Local data is enough to render the app. Billing, cloud and notification
    // plugins continue after the first useful frame instead of blocking it.
    if (loadError == null) unawaited(_initializeDeferredServices());
  }

  Future<void> _initializeDeferredServices() async {
    try {
      await subscriptions.initialize();
      billingAvailable = subscriptions.isAvailable;
      billingError = subscriptions.setupError;
      notifyListeners();
    } catch (error) {
      billingError = error.toString();
      notifyListeners();
    }
    if (signedIn && emailVerified && !accountBusy) await _syncForUser();
    try {
      if (signedIn && emailVerified && !accountBusy) await subscriptions.restorePurchases();
    } catch (error) {
      billingError = error.toString();
      notifyListeners();
    }
    try {
      await notifications.initialize();
      // A concurrent login schedules its own account after activation.
      if (!accountBusy) {
      _backgroundOperations++;
      try {
      for (final item in items) {
        await notifications.scheduleFor(item, settings);
      }
      } finally { _backgroundOperations--; }
      }
    } catch (error) {
      debugPrint('Deferred notification setup failed: $error');
    }
    deferredServicesReady = true;
    notifyListeners();
  }

  PlanTier get effectivePlan {
    if (accountEnabled && (!signedIn || !emailVerified)) return PlanTier.free;
    if (_isPlusTester) return PlanTier.plus;
    final expiresAt = settings.planExpiresAt;
    if (settings.plan != PlanTier.free &&
        expiresAt != null &&
        !expiresAt.isAfter(DateTime.now())) {
      return PlanTier.free;
    }
    return settings.plan;
  }

  int get countedItemCount => items.where((item) => !item.isArchived()).length;

  bool get canAdd => subscriptions.canAddItem(effectivePlan, countedItemCount);
  bool canEditItem(WarrantyItem item) =>
      !item.isArchived() &&
      countedItemCount <= effectivePlan.itemLimit &&
      effectivePlan.index >= item.createdOnPlan.index;
  String billingPrice(PlanTier tier) => subscriptions.priceFor(tier);
  String newId() => _uuid.v4();

  Future<void> purchasePlan(PlanTier tier) async {
    if (accountBusy || loadError != null) throw StateError('account-busy');
    if (tier == PlanTier.free) return;
    if (!signedIn || !emailVerified || cloud == null) {
      throw StateError('verified-account-required');
    }
    billingError = null;
    billingBusy = true;
    notifyListeners();
    bool launched;
    try {
      launched = await subscriptions.purchase(tier, currentPlan: settings.plan);
    } catch (error) {
      billingBusy = false;
      billingError = error.toString();
      notifyListeners();
      rethrow;
    }
    if (!launched) {
      billingBusy = false;
      billingError =
          subscriptions.setupError ?? 'Google Play Billing is unavailable.';
      notifyListeners();
      throw StateError(billingError!);
    }
  }

  Future<void> restorePurchases() async {
    if (accountBusy || loadError != null) throw StateError('account-busy');
    if (!signedIn || !emailVerified || cloud == null) {
      throw StateError('verified-account-required');
    }
    billingError = null;
    billingBusy = true;
    notifyListeners();
    try {
      await subscriptions.restorePurchases().timeout(
        const Duration(seconds: 18),
      );
    } on TimeoutException {
      billingError = 'Google Play did not respond. Please try again.';
      rethrow;
    } catch (error) {
      billingError = error.toString();
      rethrow;
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
    if (accountBusy) return; // Restore is retried after the account switch commits.
    billingBusy = true;
    _backgroundOperations++;
    notifyListeners();
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
        paidExpiresAt: entitlement.paidExpiresAt,
        referralPlusUntil: entitlement.referralPlusUntil,
        nextBillingAt: entitlement.nextBillingAt,
        updateSubscriptionDates: true,
      );
      await storage.save(items, settings);
      billingError = null;
      if (settings.plan.hasCloud) await _syncForUser();
    } catch (error) {
      billingError = error.toString();
    } finally {
      _backgroundOperations--;
      billingBusy = false;
      notifyListeners();
    }
  }

  Future<void> upsert(WarrantyItem item) async {
    if (accountBusy || loadError != null) throw StateError('account-busy');
    _localWrites++;
    try { return await _upsert(item); } finally { _localWrites--; notifyListeners(); }
  }

  Future<void> _upsert(WarrantyItem item) async {
    final index = items.indexWhere((entry) => entry.id == item.id);
    // Existing imports/edits are not new local creates. Preserve a failed
    // first save's eligibility for its successful retry.
    if (index >= 0 && !_pendingCreationIds.contains(item.id))
      _committedWarrantyIds.add(item.id);
    final removedPhotos = <String>[];
    if (index < 0) {
      if (!canAdd) throw StateError('plan_limit');
      if (item.createdOnPlan != effectivePlan) {
        throw StateError('plan_changed');
      }
      _pendingCreationIds.add(item.id);
      items = [...items, item];
    } else {
      final previous = items[index];
      if (!canEditItem(previous)) throw StateError('plan_edit_locked');
      if (item.createdOnPlan != previous.createdOnPlan) {
        throw StateError('plan_origin_immutable');
      }
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
    if (_committedWarrantyIds.add(item.id)) {
      unawaited(analytics?.warrantyCreated() ?? Future<void>.value());
    }
    _pendingCreationIds.remove(item.id);
    for (final path in removedPhotos) await photos.delete(path);
    await notifications.scheduleFor(item, settings);
    await _cloudAction(() => cloud!.saveItem(user!.uid, item));
  }

  Future<bool> delete(WarrantyItem item) async {
    if (accountBusy || loadError != null) throw StateError('account-busy');
    _localWrites++;
    try { return await _delete(item); } finally { _localWrites--; notifyListeners(); }
  }

  Future<bool> _delete(WarrantyItem item) async {
    // For cloud-backed plans, delete the remote record first. Removing the
    // local copy while the cloud delete is still pending (or has failed)
    // allows the next refresh to download the item again.
    if (signedIn && emailVerified && cloud != null && effectivePlan.hasCloud) {
      cloudError = null;
      cloudSyncing = true;
      notifyListeners();
      try {
        await cloud!.deleteItem(user!.uid, item.id);
        lastCloudSync = DateTime.now();
      } catch (error) {
        cloudError = error.toString();
        return false;
      } finally {
        cloudSyncing = false;
        notifyListeners();
      }
    }
    items = items.where((entry) => entry.id != item.id).toList();
    if (signedIn &&
        settings.cloudOwnerUid == user!.uid &&
        !effectivePlan.hasCloud &&
        !settings.pendingCloudDeletionIds.contains(item.id)) {
      settings = settings.copyWith(
        pendingCloudDeletionIds: [...settings.pendingCloudDeletionIds, item.id],
      );
    }
    await notifications.cancelFor(item.id);
    for (final path in [
      if (item.productPhoto != null) item.productPhoto!,
      ...item.receiptPhotos,
      ...item.warrantyPhotos,
    ])
      await photos.delete(path);
    await _persist();
    return true;
  }

  Future<String?> addPhoto({
    required String itemId,
    required String kind,
    required ImageSource source,
  }) => photos.capture(source, itemId, kind);

  Future<void> updateSettings(AppSettings value) async {
    if (accountBusy || loadError != null) throw StateError('account-busy');
    _localWrites++;
    try { return await _updateSettings(value); } finally { _localWrites--; notifyListeners(); }
  }

  Future<void> _updateSettings(AppSettings value) async {
    settings = value;
    await _persist();
    for (final item in items) await notifications.scheduleFor(item, settings);
    await _cloudAction(() => cloud!.saveProfile(user!.uid, settings));
  }

  Future<void> _activateAccount({bool claimGuest = false}) async {
    final previous = List<WarrantyItem>.of(items);
    try {
      if (storage is AccountLocalStore) {
        final result = await (storage as AccountLocalStore).activate(
          user?.uid, email: user?.email, claimGuest: claimGuest,
        );
        items = result.$1;
        settings = result.$2;
      }
      _committedWarrantyIds..clear()..addAll(items.map((e) => e.id));
      _pendingCreationIds.clear();
      _cloudBootstrapPending = true;
      lastCloudSync = null;
      cloudError = null;
      billingError = null;
    } catch (error) {
      // Authentication may already have changed. Never render the old owner's
      // records under the new identity if the atomic disk switch failed.
      loadError = error.toString();
      rethrow;
    }
    try {
      for (final item in previous) { await notifications.cancelFor(item.id); }
      for (final item in items) { await notifications.scheduleFor(item, settings); }
    } catch (error) { debugPrint('Account reminder scheduling failed: $error'); }
  }

  Future<void> _authenticate(Future<void> Function() action, {Future<void> Function()? configure}) async {
    if (accountActionBusy) throw StateError('account-busy');
    accountBusy = true;
    notifyListeners();
    final previousUid = user?.uid;
    try {
      await storage.save(items, settings);
      try {
        await action();
      } finally {
        // Creating Auth can succeed even when its verification email fails.
        // Bind the correct local vault in that case too.
        if (user?.uid != previousUid) {
          await _activateAccount(claimGuest: previousUid == null);
          if (signedIn) await configure?.call();
        }
      }
      if (signedIn && emailVerified) await _syncForUser();
    } finally {
      accountBusy = false;
      notifyListeners();
    }
    if (signedIn && emailVerified) {
      try { await restorePurchases(); } catch (_) { /* Login remains valid offline. */ }
    }
  }

  Future<void> createAccount({
    required String firstName, required String lastName,
    required String email, required String password, String referralCode = '',
  }) async {
    final normalizedReferral = ReferralPolicy.normalize(referralCode);
    if (normalizedReferral.isNotEmpty && !ReferralPolicy.isValid(normalizedReferral)) {
      throw const FormatException('invalid-referral-code');
    }
    await _authenticate(() async {
      await accounts!.createAccount(email: email.trim(), password: password,
        displayName: '$firstName $lastName'.trim());
    }, configure: () async {
    settings = settings.copyWith(firstName: firstName.trim(), lastName: lastName.trim(),
      email: email.trim(), referralCode: ReferralPolicy.codeForUser(user!.uid),
      pendingReferralCode: normalizedReferral);
    await _persist();
    await cloud?.registerReferralSignup(uid: user!.uid,
      ownCode: settings.referralCode, invitedByCode: normalizedReferral, email: email.trim());
    });
  }

  Future<void> signIn(String email, String password) => _authenticate(() async {
    await accounts!.signIn(email.trim(), password);
  });

  Future<void> signInWithGoogle() => _authenticate(() async {
    await accounts!.signInWithGoogle();
  });

  Future<void> sendPasswordReset(String email) =>
      accounts!.resetPassword(email.trim());
  Future<void> resendVerification() => accounts!.resendVerification();

  Future<bool> checkVerification() async {
    if (accountActionBusy) throw StateError('account-busy');
    accountBusy = true;
    notifyListeners();
    var verified = false;
    try {
      verified = await accounts!.reloadVerification();
      if (verified) await _syncForUser();
    } finally { accountBusy = false; notifyListeners(); }
    if (verified) {
      try { await restorePurchases(); } catch (_) { /* Verification succeeded. */ }
    }
    return verified;
  }

  Future<void> signOut() async {
    if (accountActionBusy) throw StateError('account-busy');
    accountBusy = true;
    notifyListeners();
    try {
      await storage.save(items, settings);
      try { await accounts!.signOut(); }
      finally { if (!signedIn) await _activateAccount(); }
    } finally { accountBusy = false; notifyListeners(); }
  }

  Future<void> deleteAccount({String? password}) async {
    if (accountActionBusy) throw StateError('account-busy');
    accountBusy = true;
    notifyListeners();
    final uid = user!.uid;
    final oldItems = List<WarrantyItem>.of(items);
    try {
      await accounts!.reauthenticate(password: password);
      await cloud!.deleteUserData(uid);
      await accounts!.deleteCurrentUser();
      if (storage is AccountLocalStore) {
        await (storage as AccountLocalStore).removeAccount(uid);
        await _activateAccount();
      } else {
        items = [];
        settings = AppSettings(onboardingComplete: settings.onboardingComplete);
        await _persist();
      }
      for (final item in oldItems) {
        await notifications.cancelFor(item.id);
        for (final path in [if (item.productPhoto != null) item.productPhoto!,
          ...item.receiptPhotos, ...item.warrantyPhotos]) {
          await photos.delete(path);
        }
      }
    } catch (error) {
      if (!signedIn) loadError = error.toString();
      rethrow;
    } finally { accountBusy = false; notifyListeners(); }
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
    if (!signedIn || !emailVerified || cloud == null || cloudSyncing) return;
    cloudSyncing = true;
    notifyListeners();
    try { await _syncForUserData(); }
    finally { cloudSyncing = false; notifyListeners(); }
  }

  Future<void> _syncForUserData() async {
    final ownCode = ReferralPolicy.codeForUser(user!.uid);
    if (settings.referralCode != ownCode) {
      settings = settings.copyWith(referralCode: ownCode);
      await storage.save(items, settings);
    }
    try {
      await cloud!.registerReferralSignup(
        uid: user!.uid,
        ownCode: ownCode,
        invitedByCode: settings.pendingReferralCode,
        email: user?.email ?? settings.email,
      );
    } catch (error) {
      cloudError = error.toString();
    }
    try {
      final entitlement = await cloud!.getEntitlements();
      settings = settings.copyWith(
        plan: _isPlusTester ? PlanTier.plus : entitlement.plan,
        smartScanCredits: entitlement.smartScanCredits,
        planExpiresAt: entitlement.expiresAt,
        clearPlanExpiry: entitlement.expiresAt == null,
        paidExpiresAt: entitlement.paidExpiresAt,
        referralPlusUntil: entitlement.referralPlusUntil,
        nextBillingAt: entitlement.nextBillingAt,
        updateSubscriptionDates: true,
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
      await _flushPendingCloudDeletions();
      final result = await cloud!.bootstrap(user!.uid, items, settings);
      items = result.items;
      settings = result.settings.copyWith(
        email: user?.email ?? settings.email,
        plan: _isPlusTester ? PlanTier.plus : result.settings.plan,
      );
      await storage.save(items, settings);
      for (final item in items) { await notifications.scheduleFor(item, settings); }
      _cloudBootstrapPending = false;
      lastCloudSync = DateTime.now();
    } catch (error) {
      cloudError = error.toString();
    }
  }

  Future<void> refreshCloud() async {
    if (!signedIn || !emailVerified || cloud == null || accountBusy) return;
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
      await _flushPendingCloudDeletions();
      final entitlement = await cloud!.getEntitlements();
      settings = settings.copyWith(
        plan: _isPlusTester ? PlanTier.plus : entitlement.plan,
        smartScanCredits: entitlement.smartScanCredits,
        planExpiresAt: entitlement.expiresAt,
        clearPlanExpiry: entitlement.expiresAt == null,
        paidExpiresAt: entitlement.paidExpiresAt,
        referralPlusUntil: entitlement.referralPlusUntil,
        nextBillingAt: entitlement.nextBillingAt,
        updateSubscriptionDates: true,
      );
      final result = _cloudBootstrapPending
          ? await cloud!.bootstrap(user!.uid, items, settings)
          : await cloud!.refresh(user!.uid, settings);
      items = result.items;
      settings = result.settings.copyWith(
        email: user?.email ?? settings.email,
        plan: _isPlusTester ? PlanTier.plus : result.settings.plan,
      );
      await storage.save(items, settings);
      for (final item in items) {
        await notifications.scheduleFor(item, settings);
      }
      _cloudBootstrapPending = false;
      lastCloudSync = DateTime.now();
    } catch (error) {
      cloudError = error.toString();
    } finally {
      cloudSyncing = false;
      notifyListeners();
    }
  }

  Future<void> redeemFounderCode(String code) async {
    if (accountActionBusy) throw StateError('account-busy');
    _localWrites++;
    try { await _redeemFounderCode(code); } finally { _localWrites--; notifyListeners(); }
  }

  Future<void> _redeemFounderCode(String code) async {
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
    if (accountBusy || loadError != null) throw StateError('account-busy');
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

  Future<void> _flushPendingCloudDeletions() async {
    if (cloud == null || !signedIn || settings.cloudOwnerUid != user!.uid)
      return;
    for (final id in List<String>.of(settings.pendingCloudDeletionIds)) {
      // Keep each ID on disk until its cloud deletion succeeds. A failed
      // deletion aborts refresh so a stale record is never downloaded again.
      await cloud!.deleteItem(user!.uid, id);
      settings = settings.copyWith(
        pendingCloudDeletionIds: settings.pendingCloudDeletionIds
            .where((pending) => pending != id)
            .toList(),
      );
      await storage.save(items, settings);
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
  void notifyListeners() {
    // Startup/billing/cloud futures can finish after the provider is removed.
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    final billingSubscription = _billingSubscription;
    if (billingSubscription != null) {
      unawaited(billingSubscription.cancel());
    }
    unawaited(subscriptions.dispose());
    super.dispose();
  }
}
