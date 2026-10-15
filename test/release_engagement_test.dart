import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:warranty_cave/data/play_review.dart';
import 'package:warranty_cave/data/play_updates.dart';
import 'package:warranty_cave/data/services.dart';
import 'package:warranty_cave/domain/models.dart';
import 'package:warranty_cave/l10n/app_localizations.dart';
import 'package:warranty_cave/presentation/app_controller.dart';
import 'package:warranty_cave/presentation/release_engagement_host.dart';
import 'package:warranty_cave/presentation/theme.dart';

Widget localized(Widget child, {String code = 'en', bool dark = false}) =>
    MaterialApp(
      theme: dark ? buildDarkTheme() : buildTheme(),
      locale: Locale(code),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      navigatorObservers: [engagementRouteObserver],
      home: child,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'optional analytics choice fits narrow screens in all eight languages and themes',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final dark in [false, true]) {
        for (final locale in AppLocalizations.supportedLocales) {
          bool? result;
          final l10n = AppLocalizations(locale);
          await tester.pumpWidget(
            localized(
              Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () async {
                      result = await showUsageConsent(context);
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
              code: locale.languageCode,
              dark: dark,
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '${locale.languageCode}/$dark',
          );
          expect(find.text(l10n.text('usageMeasurementTitle')), findsOneWidget);
          await tester.tap(find.text(l10n.text('metaNotNow')));
          await tester.pumpAndSettle();
          expect(result, false);
          expect(find.byType(AlertDialog), findsNothing);
          await tester.pumpWidget(const SizedBox());
        }
      }
    },
  );
  testWidgets(
    'review waits for update query and cannot interrupt an editor',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final reviews = _Reviews();
      final app = _App(reviews);
      final updates = _Updates();
      updates.change(const PlayUpdateState(checking: true));
      await tester.pumpWidget(
        ChangeNotifierProvider<AppController>.value(
          value: app,
          child: localized(
            ReleaseEngagementHost(
              mainReady: true,
              updates: updates,
              child: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    child: const Text('Editor'),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const Scaffold(body: TextField()),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(reviews.calls, 0);
      await tester.tap(find.text('Editor'));
      await tester.pumpAndSettle();
      updates.change(const PlayUpdateState());
      await tester.pump(const Duration(seconds: 2));
      expect(reviews.calls, 0);
      Navigator.of(tester.element(find.byType(TextField))).pop();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(reviews.calls, 1);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
      updates.dispose();
    },
  );
}

class _Reviews extends PlayReview {
  int calls = 0;
  @override
  Future<void> request(int count, bool Function() stillSafe) async {
    if (stillSafe()) calls++;
  }
}

class _Updates extends PlayUpdates {
  _Updates() : super(channel: const MethodChannel('test/updates'));
  void change(PlayUpdateState value) {
    state = value;
    initialized = true;
    notifyListeners();
  }
}

class _App extends AppController {
  _App(PlayReview reviews)
    : super(
        storage: _Storage(),
        photos: LocalPhotoStorageService(),
        notifications: LocalNotificationService(),
        subscriptions: LocalSubscriptionService(),
        reviews: reviews,
      ) {
    loading = false;
    deferredServicesReady = true;
  }
  @override
  bool get signedIn => true;
  @override
  bool get emailVerified => true;
}

class _Storage implements LocalStorageService {
  @override
  Future<(List<WarrantyItem>, AppSettings)> load() async =>
      ([], const AppSettings());
  @override
  Future<void> save(List<WarrantyItem> items, AppSettings settings) async {}
}
