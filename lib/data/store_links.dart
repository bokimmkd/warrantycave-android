import 'package:flutter/foundation.dart';
import '../domain/models.dart';

abstract final class StoreLinks {
  // Assigned only after creating WarrantyCave in App Store Connect.
  static const appleAppId = String.fromEnvironment('IOS_APP_STORE_ID');
  static String get download => defaultTargetPlatform == TargetPlatform.iOS
      ? (appleAppId.isEmpty
            ? 'https://warrantycave.com'
            : 'https://apps.apple.com/app/id$appleAppId')
      : ReferralPolicy.googlePlayDownloadUrl;
  static String get review =>
      defaultTargetPlatform == TargetPlatform.iOS && appleAppId.isNotEmpty
      ? '$download?action=write-review'
      : download;
}
