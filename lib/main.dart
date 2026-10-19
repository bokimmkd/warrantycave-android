import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/usage_analytics.dart';
import 'data/play_review.dart';
import 'presentation/release_engagement_host.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'data/services.dart';
import 'data/play_billing_service.dart';
import 'data/ad_service.dart';
import 'data/firebase_services.dart';
import 'firebase_options.dart';
import 'l10n/app_localizations.dart';
import 'presentation/app_controller.dart';
import 'presentation/main_shell.dart';
import 'presentation/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: WarrantyCaveFirebaseOptions.android);
  final legacyNavigation =
      await const MethodChannel('com.warrantycave.app/system_ui')
          .invokeMethod<bool>('legacyNavigation') ??
      true;
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final analytics = UsageAnalytics();
  await analytics.initialize();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppController(
        storage: JsonLocalStorageService(),
        photos: LocalPhotoStorageService(),
        notifications: LocalNotificationService(),
        subscriptions: GooglePlaySubscriptionService(),
        accounts: FirebaseAccountService(analytics: analytics),
        analytics: analytics,
        reviews: PlayReview(),
        cloud: FirebaseCloudService(),
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
