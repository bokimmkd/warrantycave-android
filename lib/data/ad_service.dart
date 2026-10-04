import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

abstract final class AdService {
  static const _testBannerId = 'ca-app-pub-3940256099942544/6300978111';
  static const _productionBannerId =
      'ca-app-pub-1171723950608276/9463569777';

  static String get _bannerId =>
      kDebugMode ? _testBannerId : _productionBannerId;

  static Future<void>? _initialization;

  static Future<void> initialize() =>
      _initialization ??= _initializeOnce();

  static Future<void> _initializeOnce() async {
    final consent = ConsentInformation.instance;
    final consentResolved = Completer<void>();
    consent.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () {
        ConsentForm.loadAndShowConsentFormIfRequired((_) {
          if (!consentResolved.isCompleted) consentResolved.complete();
        });
      },
      (_) {
        // UMP may still allow ads using consent from a previous session.
        if (!consentResolved.isCompleted) consentResolved.complete();
      },
    );
    await consentResolved.future;
    if (await consent.canRequestAds()) {
      await MobileAds.instance.initialize();
    }
  }

  static Future<bool> canLoadAds() async {
    await initialize();
    return ConsentInformation.instance.canRequestAds();
  }

  static Future<bool> privacyOptionsRequired() async {
    await initialize();
    return await ConsentInformation.instance
            .getPrivacyOptionsRequirementStatus() ==
        PrivacyOptionsRequirementStatus.required;
  }

  static Future<void> showPrivacyOptions() async {
    final done = Completer<void>();
    ConsentForm.showPrivacyOptionsForm((_) => done.complete());
    await done.future;
  }

  static BannerAd banner({
    required AdSize size,
    required VoidCallback onLoaded,
    required VoidCallback onFailed,
  }) => BannerAd(
    adUnitId: _bannerId,
    size: size,
    request: const AdRequest(),
    listener: BannerAdListener(
      onAdLoaded: (_) => onLoaded(),
      onAdFailedToLoad: (ad, _) {
        ad.dispose();
        onFailed();
      },
    ),
  );
}

class FreeBannerAd extends StatefulWidget {
  const FreeBannerAd({super.key});

  @override
  State<FreeBannerAd> createState() => _FreeBannerAdState();
}

class _FreeBannerAdState extends State<FreeBannerAd> {
  BannerAd? ad;
  bool loaded = false;
  int _width = 0;
  Orientation? _orientation;
  int _generation = 0;

  Future<void> _load(int width, int generation) async {
    if (!await AdService.canLoadAds() || !mounted || generation != _generation) return;
    final size = await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(width);
    if (size == null || !mounted || generation != _generation) return;
    final banner = AdService.banner(size: size,
      onLoaded: () { if (mounted && generation == _generation) setState(() => loaded = true); },
      onFailed: () { if (mounted && generation == _generation) setState(() { loaded = false; ad = null; }); },
    );
    ad = banner;
    await banner.load();
  }

  @override
  void dispose() { _generation++; ad?.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final width = constraints.maxWidth.floor();
    final orientation = MediaQuery.orientationOf(context);
    if (width > 0 && (width != _width || orientation != _orientation)) {
      _width = width; _orientation = orientation;
      final generation = ++_generation;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || generation != _generation) return;
        ad?.dispose(); ad = null;
        setState(() => loaded = false);
        unawaited(_load(width, generation));
      });
      return const SizedBox.shrink();
    }
    if (!loaded || ad == null) return const SizedBox.shrink();
    return ColoredBox(color: Theme.of(context).colorScheme.surface,
      child: SizedBox(width: ad!.size.width.toDouble(), height: ad!.size.height.toDouble(),
        child: AdWidget(ad: ad!)));
  });
}
