import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

abstract final class AdService {
  static const _bannerId = String.fromEnvironment(
    'ADMOB_BANNER_ID',
    defaultValue: 'ca-app-pub-3940256099942544/6300978111',
  );

  static Future<void> initialize() async {
    await MobileAds.instance.initialize();
    final consent = ConsentInformation.instance;
    consent.requestConsentInfoUpdate(ConsentRequestParameters(), () async {
      if (await consent.isConsentFormAvailable()) {
        await ConsentForm.loadAndShowConsentFormIfRequired((_) {});
      }
    }, (_) {});
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
    ad = AdService.banner(
      onLoaded: () {
        if (mounted) setState(() => loaded = true);
      },
      onFailed: () {
        if (mounted) setState(() => loaded = false);
      },
    )..load();
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
