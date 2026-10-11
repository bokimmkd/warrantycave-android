import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_service.dart';

/// One independently owned ad per list slot. A slot is never re-requested by
/// build/scroll callbacks; the list owns it until its width or entitlement changes.
abstract interface class InlineBanner {
  Future<Size?> load();
  Widget buildAd();
  void dispose();
}

typedef InlineBannerFactory = InlineBanner Function(int width, int maxHeight);

InlineBanner createInlineBanner(int width, int maxHeight) =>
    _AdMobInlineBanner(width, maxHeight);

class _AdMobInlineBanner implements InlineBanner {
  _AdMobInlineBanner(this.width, this.maxHeight);
  final int width;
  final int maxHeight;
  BannerAd? _ad;
  bool _disposed = false;
  final _result = Completer<Size?>();

  void _finish(Size? size) {
    if (!_result.isCompleted) _result.complete(size);
  }

  @override
  Future<Size?> load() async {
    try {
      if (!await AdService.canLoadAds() || _disposed) return null;
      final ad = BannerAd(
        adUnitId: AdService.inlineBannerId,
        size: AdSize.getInlineAdaptiveBannerAdSize(width, maxHeight),
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) async {
            try {
              final size = await (ad as BannerAd).getPlatformAdSize();
              if (_disposed) return;
              if (size == null || size.height <= 0 ||
                  size.height > maxHeight || size.width > width) {
                dispose();
                return;
              }
              _finish(Size(size.width.toDouble(), size.height.toDouble()));
            } catch (_) {
              dispose();
            }
          },
          onAdFailedToLoad: (_, _) => dispose(),
        ),
      );
      if (_disposed) return null;
      _ad = ad;
      await ad.load();
      return await _result.future.timeout(const Duration(seconds: 12),
        onTimeout: () { dispose(); return null; });
    } catch (_) {
      dispose();
      return null;
    }
  }

  @override
  Widget buildAd() => _ad == null || _disposed
      ? const SizedBox.shrink() : AdWidget(ad: _ad!);

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _finish(null);
    unawaited(_ad?.dispose());
    _ad = null;
  }
}
