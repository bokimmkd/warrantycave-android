import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'data/services.dart';
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
  await AdService.initialize();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppController(
        storage: JsonLocalStorageService(),
        photos: LocalPhotoStorageService(),
        notifications: LocalNotificationService(),
        subscriptions: LocalSubscriptionService(),
        accounts: FirebaseAccountService(),
        cloud: FirebaseCloudService(),
      )..initialize(),
      child: const WarrantyCaveApp(),
    ),
  );
}

class WarrantyCaveApp extends StatelessWidget {
  const WarrantyCaveApp({super.key});
  @override
  Widget build(BuildContext context) {
    final languageCode = context.select<AppController, String>(
      (app) => app.settings.languageCode,
    );
    return MaterialApp(
      title: 'WarrantyCave',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      locale: Locale(languageCode),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const MainShell(),
    );
  }
}
