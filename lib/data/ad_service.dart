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
    required VoidCallback onLoaded,
    required VoidCallback onFailed,
  }) => BannerAd(
    adUnitId: _bannerId,
    size: AdSize.banner,
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!await AdService.canLoadAds() || !mounted) return;
    final banner = AdService.banner(
      onLoaded: () {
        if (mounted) setState(() => loaded = true);
      },
      onFailed: () {
        if (mounted) setState(() => loaded = false);
      },
    );
    ad = banner;
    banner.load();
  }

  @override
  void dispose() {
    ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded || ad == null) return const SizedBox.shrink();
    return ColoredBox(
      color: Colors.white,
      child: SafeArea(
        top: false,
        bottom: false,
        child: SizedBox(
          width: ad!.size.width.toDouble(),
          height: ad!.size.height.toDouble(),
          child: AdWidget(ad: ad!),
        ),
      ),
    );
  }
}
