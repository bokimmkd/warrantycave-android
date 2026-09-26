import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import '../domain/models.dart';
import 'services.dart';

class FirebaseAccountService {
  FirebaseAccountService({FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;
  static const _googleServerClientId =
      '491401464312-pkie3i2v4dc1h3r3sbcoub7kp3g2tvto.apps.googleusercontent.com';
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: _googleServerClientId,
  );

  User? get currentUser => _auth.currentUser;
  bool get usesPassword =>
      currentUser?.providerData.any(
        (provider) => provider.providerId == 'password',
      ) ??
      false;

  Future<User> createAccount({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final result = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = result.user!;
    await user.updateDisplayName(displayName.trim());
    await user.sendEmailVerification();
    await user.reload();
    return _auth.currentUser!;
  }

  Future<User> signIn(String email, String password) async =>
      (await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      )).user!;

  Future<User> signInWithGoogle() async {
    // Match School Assistant: clear the previous Google selection before
    // requesting an ID token for the Firebase web OAuth client.
    await _googleSignIn.signOut();
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      throw FirebaseAuthException(
        code: 'google-sign-in-canceled',
        message: 'Google sign-in was canceled.',
      );
    }
    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
      accessToken: googleAuth.accessToken,
    );
    return (await _auth.signInWithCredential(credential)).user!;
  }

  Future<void> resetPassword(String email) =>
      _auth.sendPasswordResetEmail(email: email);

  Future<void> resendVerification() async =>
      currentUser?.sendEmailVerification();

  Future<bool> reloadVerification() async {
    await currentUser?.reload();
    return _auth.currentUser?.emailVerified ?? false;
  }

  Future<void> signOut() async {
    await _auth.signOut();
    await _googleSignIn.signOut();
  }

  Future<void> reauthenticate({String? password}) async {
    final user = currentUser;
    if (user == null) return;
    if (usesPassword) {
      if (password == null || password.isEmpty) {
        throw FirebaseAuthException(code: 'password-required');
      }
      final email = user.email;
      if (email == null) throw FirebaseAuthException(code: 'missing-email');
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: password),
      );
    } else {
      await _googleSignIn.signOut();
      final account = await _googleSignIn.signIn();
      if (account == null) {
        throw FirebaseAuthException(
          code: 'google-sign-in-canceled',
          message: 'Google sign-in was canceled.',
        );
      }
      final authentication = await account.authentication;
      await user.reauthenticateWithCredential(
        GoogleAuthProvider.credential(
          idToken: authentication.idToken,
          accessToken: authentication.accessToken,
        ),
      );
    }
  }

  Future<void> deleteCurrentUser() async => currentUser?.delete();
}

class CloudBootstrapResult {
  const CloudBootstrapResult(this.items, this.settings);
  final List<WarrantyItem> items;
  final AppSettings settings;
}

class EntitlementResult {
  const EntitlementResult({
    required this.plan,
    required this.smartScanCredits,
    this.expiresAt,
  });
  final PlanTier plan;
  final int smartScanCredits;
  final DateTime? expiresAt;
}

class FirebaseCloudService {
  FirebaseCloudService({FirebaseFirestore? firestore, http.Client? httpClient})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _http = httpClient ?? http.Client();

  final FirebaseFirestore _firestore;
  final http.Client _http;

  String get _bucket => Firebase.app().options.storageBucket!;

  DocumentReference<Map<String, dynamic>> _profile(String uid) =>
      _firestore.collection('users').doc(uid);
  CollectionReference<Map<String, dynamic>> _items(String uid) =>
      _profile(uid).collection('items');

  Uri _functionUri(String name) => Uri.parse(
    'https://us-central1-${Firebase.app().options.projectId}.cloudfunctions.net/$name',
  );

  Future<Map<String, dynamic>> _callFunction(
    String name,
    Map<String, dynamic> data,
  ) async {
    final response = await _http.post(
      _functionUri(name),
      headers: await _authHeaders(contentType: 'application/json'),
      body: jsonEncode({'data': data}),
    );
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded['error'] as Map<String, dynamic>?;
      throw StateError(
        error?['message'] as String? ?? 'Server request failed.',
      );
    }
    return Map<String, dynamic>.from(decoded['result'] as Map? ?? const {});
  }

  Future<EntitlementResult> getEntitlements() async {
    final result = await _callFunction('getEntitlements', const {});
    final planName = result['plan'] as String? ?? 'free';
    return EntitlementResult(
      plan:
          PlanTier.values.where((tier) => tier.name == planName).firstOrNull ??
          PlanTier.free,
      smartScanCredits: (result['smartScanCredits'] as num?)?.toInt() ?? 0,
      expiresAt: DateTime.tryParse(result['expiresAt'] as String? ?? ''),
    );
  }

  Future<EntitlementResult> redeemFounderCode(String code) async {
    final result = await _callFunction('redeemFounderCode', {'code': code});
    return EntitlementResult(
      plan: PlanTier.basic,
      smartScanCredits: 0,
      expiresAt: DateTime.tryParse(result['expiresAt'] as String? ?? ''),
    );
  }

  Future<EntitlementResult> confirmPlayPurchase({
    required String productId,
    required String purchaseToken,
  }) async {
    final result = await _callFunction('confirmPlayPurchase', {
      'productId': productId,
      'purchaseToken': purchaseToken,
    });
    final planName = result['plan'] as String? ?? 'free';
    return EntitlementResult(
      plan:
          PlanTier.values.where((tier) => tier.name == planName).firstOrNull ??
          PlanTier.free,
      smartScanCredits: 0,
      expiresAt: DateTime.tryParse(result['expiresAt'] as String? ?? ''),
    );
  }

  Future<ScanSuggestion> smartScanReceipt(String localImagePath) async {
    final bytes = await File(localImagePath).readAsBytes();
    final result = await _callFunction('smartScanReceipt', {
      'imageBase64': base64Encode(bytes),
    });
    return ScanSuggestion(
      store: result['store'] as String?,
      purchaseDate: DateTime.tryParse(result['purchaseDate'] as String? ?? ''),
      price: (result['price'] as num?)?.toDouble(),
      productName: result['productName'] as String?,
      brand: result['brand'] as String?,
      model: result['model'] as String?,
      serialNumber: result['serialNumber'] as String?,
      currency: result['currency'] as String?,
      remainingCredits: (result['remainingCredits'] as num?)?.toInt(),
    );
  }

  Future<CloudBootstrapResult> bootstrap(
    String uid,
    List<WarrantyItem> localItems,
    AppSettings localSettings,
  ) async {
    final profileSnapshot = await _profile(uid).get();
    var mergedSettings = localSettings;
    final remoteProfile = profileSnapshot.data();
    if (remoteProfile != null) {
      mergedSettings = localSettings.copyWith(
        firstName:
            remoteProfile['firstName'] as String? ?? localSettings.firstName,
        lastName:
            remoteProfile['lastName'] as String? ?? localSettings.lastName,
        phone: remoteProfile['phone'] as String? ?? localSettings.phone,
        defaultCurrency:
            remoteProfile['defaultCurrency'] as String? ??
            localSettings.defaultCurrency,
        languageCode:
            remoteProfile['languageCode'] as String? ??
            localSettings.languageCode,
        referralCode:
            remoteProfile['referralCode'] as String? ??
            localSettings.referralCode,
        pendingReferralCode:
            remoteProfile['pendingReferralCode'] as String? ??
            localSettings.pendingReferralCode,
        smartScanCredits:
            (remoteProfile['smartScanCredits'] as num?)?.toInt() ??
            localSettings.smartScanCredits,
      );
    }
    final ownsLocalData =
        localSettings.cloudOwnerUid.isEmpty ||
        localSettings.cloudOwnerUid == uid;
    if (localItems.isNotEmpty && ownsLocalData) {
      mergedSettings = mergedSettings.copyWith(cloudOwnerUid: uid);
      await saveProfile(uid, mergedSettings);
      for (final item in localItems) await saveItem(uid, item);
      return CloudBootstrapResult(localItems, mergedSettings);
    }
    final remote = await _items(
      uid,
    ).orderBy('createdAt', descending: true).get();
    final downloaded = remote.docs
        .map((doc) => WarrantyItem.fromJson(doc.data()))
        .toList();
    mergedSettings = mergedSettings.copyWith(cloudOwnerUid: uid);
    await saveProfile(uid, mergedSettings);
    return CloudBootstrapResult(downloaded, mergedSettings);
  }

  Future<CloudBootstrapResult> refresh(
    String uid,
    AppSettings localSettings,
  ) async {
    final profileSnapshot = await _profile(uid).get();
    final remoteProfile = profileSnapshot.data();
    final mergedSettings = localSettings.copyWith(
      firstName:
          remoteProfile?['firstName'] as String? ?? localSettings.firstName,
      lastName: remoteProfile?['lastName'] as String? ?? localSettings.lastName,
      phone: remoteProfile?['phone'] as String? ?? localSettings.phone,
      defaultCurrency:
          remoteProfile?['defaultCurrency'] as String? ??
          localSettings.defaultCurrency,
      languageCode:
          remoteProfile?['languageCode'] as String? ??
          localSettings.languageCode,
      referralCode:
          remoteProfile?['referralCode'] as String? ??
          localSettings.referralCode,
      pendingReferralCode:
          remoteProfile?['pendingReferralCode'] as String? ??
          localSettings.pendingReferralCode,
      smartScanCredits:
          (remoteProfile?['smartScanCredits'] as num?)?.toInt() ??
          localSettings.smartScanCredits,
      cloudOwnerUid: uid,
    );
    final remote = await _items(
      uid,
    ).orderBy('createdAt', descending: true).get();
    return CloudBootstrapResult(
      remote.docs.map((doc) => WarrantyItem.fromJson(doc.data())).toList(),
      mergedSettings,
    );
  }

  Future<void> saveProfile(String uid, AppSettings settings) =>
      _profile(uid).set({
        'firstName': settings.firstName,
        'lastName': settings.lastName,
        'phone': settings.phone,
        'defaultCurrency': settings.defaultCurrency,
        'languageCode': settings.languageCode,
        if (settings.referralCode.isNotEmpty)
          'referralCode': settings.referralCode,
        if (settings.pendingReferralCode.isNotEmpty)
          'pendingReferralCode': settings.pendingReferralCode,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  /// Registers the user's deterministic code and optional inviter through the
  /// trusted backend. Rewards are granted only after Play verifies a purchase.
  Future<void> registerReferralSignup({
    required String uid,
    required String ownCode,
    required String invitedByCode,
    required String email,
  }) async {
    final normalizedInviter = ReferralPolicy.normalize(invitedByCode);
    if (!ReferralPolicy.isValid(ReferralPolicy.normalize(ownCode))) return;
    if (normalizedInviter.isNotEmpty &&
        !ReferralPolicy.isValid(normalizedInviter)) {
      throw StateError('invalid-referral-code');
    }
    if (normalizedInviter == ReferralPolicy.normalize(ownCode)) {
      throw StateError('self-referral-not-allowed');
    }
    await _callFunction('registerReferralSignup', {
      'invitedByCode': normalizedInviter,
    });
  }

  Future<void> saveItem(String uid, WarrantyItem item) async {
    final previous = (await _items(uid).doc(item.id).get()).data();
    final productPhoto = await _syncPhoto(
      uid: uid,
      itemId: item.id,
      kind: 'product',
      index: 0,
      path: item.productPhoto,
    );
    final receiptPhotos = await _syncPhotos(
      uid,
      item.id,
      'receipts',
      item.receiptPhotos,
    );
    final warrantyPhotos = await _syncPhotos(
      uid,
      item.id,
      'warranty',
      item.warrantyPhotos,
    );

    final currentUrls = <String>{
      if (productPhoto != null) productPhoto,
      ...receiptPhotos,
      ...warrantyPhotos,
    };
    final currentPaths = currentUrls
        .map(_storagePath)
        .whereType<String>()
        .toSet();
    for (final oldUrl in _remotePhotoUrls(previous)) {
      final oldPath = _storagePath(oldUrl);
      if (oldPath != null && !currentPaths.contains(oldPath)) {
        await _deleteObject(oldPath);
      }
    }

    final json = item.toJson()
      ..['productPhoto'] = productPhoto
      ..['receiptPhotos'] = receiptPhotos
      ..['warrantyPhotos'] = warrantyPhotos
      ..['updatedAt'] = FieldValue.serverTimestamp();
    await _items(uid).doc(item.id).set(json);
  }

  Future<List<String>> _syncPhotos(
    String uid,
    String itemId,
    String kind,
    List<String> paths,
  ) async {
    final result = <String>[];
    for (final entry in paths.indexed) {
      final url = await _syncPhoto(
        uid: uid,
        itemId: itemId,
        kind: kind,
        index: entry.$1,
        path: entry.$2,
      );
      if (url != null) result.add(url);
    }
    return result;
  }

  Future<String?> _syncPhoto({
    required String uid,
    required String itemId,
    required String kind,
    required int index,
    required String? path,
  }) async {
    if (path == null || path.isEmpty) return null;
    if (_isRemote(path)) return path;
    final file = File(path);
    if (!await file.exists()) return null;
    final extension = _safeExtension(path);
    final objectPath = 'users/$uid/items/$itemId/$kind/$index$extension';
    final uri = Uri.https(
      'firebasestorage.googleapis.com',
      '/v0/b/$_bucket/o',
      {'uploadType': 'media', 'name': objectPath},
    );
    final response = await _http.post(
      uri,
      headers: await _authHeaders(contentType: _contentType(extension)),
      body: await file.readAsBytes(),
    );
    _ensureSuccess(response, 'upload-failed');
    final metadata = jsonDecode(response.body) as Map<String, dynamic>;
    final tokens = (metadata['downloadTokens'] as String? ?? '')
        .split(',')
        .where((token) => token.isNotEmpty)
        .toList();
    if (tokens.isEmpty) {
      throw StateError('Cloud upload completed without a download token.');
    }
    final downloadUri = Uri.parse(
      'https://firebasestorage.googleapis.com/v0/b/$_bucket/o/'
      '${Uri.encodeComponent(objectPath)}',
    );
    return downloadUri
        .replace(queryParameters: {'alt': 'media', 'token': tokens.first})
        .toString();
  }

  bool _isRemote(String value) =>
      value.startsWith('https://') || value.startsWith('gs://');

  String _safeExtension(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return '.jpg';
    final extension = path.substring(dot).toLowerCase();
    return const {'.jpg', '.jpeg', '.png', '.webp'}.contains(extension)
        ? extension
        : '.jpg';
  }

  String _contentType(String extension) => switch (extension) {
    '.png' => 'image/png',
    '.webp' => 'image/webp',
    _ => 'image/jpeg',
  };

  String? _storagePath(String url) {
    try {
      final repaired = url.replaceAllMapped(
        RegExp(r'%25([0-9A-Fa-f]{2})'),
        (match) => '%${match.group(1)}',
      );
      final uri = Uri.parse(repaired);
      if (uri.scheme == 'gs') {
        return uri.pathSegments.join('/');
      }
      final marker = uri.pathSegments.indexOf('o');
      if (marker < 0 || marker + 1 >= uri.pathSegments.length) return null;
      return uri.pathSegments.sublist(marker + 1).join('/');
    } catch (_) {
      return null;
    }
  }

  Iterable<String> _remotePhotoUrls(Map<String, dynamic>? json) sync* {
    if (json == null) return;
    final product = json['productPhoto'];
    if (product is String && _isRemote(product)) yield product;
    for (final key in ['receiptPhotos', 'warrantyPhotos']) {
      for (final value in json[key] as List? ?? const []) {
        if (value is String && _isRemote(value)) yield value;
      }
    }
  }

  Future<void> deleteItem(String uid, String itemId) async {
    final document = _items(uid).doc(itemId);
    final data = (await document.get()).data();
    // The Firestore record is the source of truth during sync. Delete it
    // before cleaning up Storage so a missing/locked photo can never leave a
    // live record that gets downloaded again.
    await document.delete();
    for (final url in _remotePhotoUrls(data)) {
      final path = _storagePath(url);
      if (path != null) {
        try {
          await _deleteObject(path);
        } catch (_) {
          // An orphaned image is preferable to resurrecting the warranty.
          // It can be cleaned up later without blocking record deletion.
        }
      }
    }
  }

  Future<void> deleteUserData(String uid) async {
    final snapshot = await _items(uid).get();
    for (final document in snapshot.docs) {
      for (final url in _remotePhotoUrls(document.data())) {
        final path = _storagePath(url);
        if (path != null) await _deleteObject(path);
      }
    }
    var batch = _firestore.batch();
    var count = 0;
    for (final document in snapshot.docs) {
      batch.delete(document.reference);
      count++;
      if (count == 450) {
        await batch.commit();
        batch = _firestore.batch();
        count = 0;
      }
    }
    if (count > 0) await batch.commit();
    await _profile(uid).delete();
  }

  Future<Map<String, String>> _authHeaders({String? contentType}) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('Sign in is required for cloud storage.');
    }
    return {
      'Authorization': 'Bearer $token',
      if (contentType != null) 'Content-Type': contentType,
    };
  }

  Future<void> _deleteObject(String objectPath) async {
    final uri = Uri.https(
      'firebasestorage.googleapis.com',
      '/v0/b/$_bucket/o/${Uri.encodeComponent(objectPath)}',
    );
    final response = await _http.delete(uri, headers: await _authHeaders());
    if (response.statusCode == 404) return;
    _ensureSuccess(response, 'delete-failed');
  }

  void _ensureSuccess(http.Response response, String operation) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw FirebaseException(
      plugin: 'firebase_storage',
      code: operation,
      message: 'Cloud Storage returned ${response.statusCode}.',
    );
  }
}
