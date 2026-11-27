import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'data/usage_analytics.dart';
import 'data/play_review.dart';
import 'presentation/release_engagement_host.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'data/services.dart';
import 'data/play_billing_service.dart';
import 'data/apple_billing_service.dart';
import 'data/ad_service.dart';
import 'data/firebase_services.dart';
import 'firebase_options.dart';
import 'l10n/app_localizations.dart';
import 'presentation/app_controller.dart';
import 'presentation/main_shell.dart';
import 'presentation/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The native iOS Firebase app is a separate registration in the same project.
  // Only explicit local simulator builds may run without that registration.
  const localOnly = bool.fromEnvironment('IOS_LOCAL_ONLY');
  final isIOS = defaultTargetPlatform == TargetPlatform.iOS;
  if (localOnly && kReleaseMode) {
    throw StateError('Local-only builds cannot be released.');
  }
  final useFirebase = !(isIOS && localOnly);
  if (useFirebase) {
    await Firebase.initializeApp(
      options: isIOS ? null : WarrantyCaveFirebaseOptions.android,
    );
  }
  final legacyNavigation =
      defaultTargetPlatform == TargetPlatform.android &&
      (await const MethodChannel(
            'com.warrantycave.app/system_ui',
          ).invokeMethod<bool>('legacyNavigation') ??
          true);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final analytics = UsageAnalytics();
  await analytics.initialize();
  final cloud = useFirebase ? FirebaseCloudService() : null;
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppController(
        storage: JsonLocalStorageService(),
        photos: LocalPhotoStorageService(),
        notifications: isIOS ? IOSNotificationService() : LocalNotificationService(),
        subscriptions: isIOS
            ? AppleSubscriptionService(
                accountToken: () async {
                  if (cloud == null) throw StateError('Sign in to continue.');
                  return cloud.appleBillingAccountToken();
                },
              )
            : GooglePlaySubscriptionService(),
        accounts: useFirebase
            ? FirebaseAccountService(analytics: analytics)
            : null,
        analytics: useFirebase ? analytics : null,
        reviews: PlayReview(),
        cloud: cloud,
      )..initialize(),
      child: WarrantyCaveApp(legacyNavigation: legacyNavigation),
    ),
  );
  // Ads and consent must never delay the first useful frame.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(AdService.initialize());
  });
}

class WarrantyCaveApp extends StatelessWidget {
  const WarrantyCaveApp({super.key, this.legacyNavigation = false});
  // Android 7 has white navigation buttons and no dark-icon API.
  final bool legacyNavigation;
  @override
  Widget build(BuildContext context) {
    final languageCode = context.select<AppController, String>(
      (app) => app.settings.languageCode,
    );
    final darkMode = context.select<AppController, bool>(
      (app) => app.settings.darkMode,
    );
    return MaterialApp(
      title: 'WarrantyCave',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
      locale: appLocale(languageCode),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      navigatorObservers: [engagementRouteObserver],
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: legacyNavigation
              ? caveNavy
              : Colors.transparent,
          statusBarIconBrightness: darkMode
              ? Brightness.light
              : Brightness.dark,
          statusBarBrightness: darkMode ? Brightness.dark : Brightness.light,
          systemNavigationBarIconBrightness: darkMode || legacyNavigation
              ? Brightness.light
              : Brightness.dark,
          systemNavigationBarContrastEnforced: true,
        ),
        child: child!,
      ),
      home: const MainShell(),
    );
  }
}
