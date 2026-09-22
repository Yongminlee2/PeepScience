import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../services/ads.dart';

/// 홈 화면 맨 아래에만 놓는 띠 광고.
///
/// 게임 화면에는 쓰지 않는다 - 거기는 가로 화면 전체가 부품을 놓는 자리라
/// 띠를 붙이면 공이나 말풍선을 가린다.
///
/// 광고를 못 받으면 높이 0이 되어 아무 자리도 차지하지 않는다. 그래서
/// 인터넷이 없거나 광고 ID를 아직 안 넣었을 때 홈 화면은 예전 그대로다.
class AdBanner extends StatefulWidget {
  const AdBanner({super.key});

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _ad;
  bool _requested = false;

  // 화면 너비를 알아야 띠 크기를 정할 수 있어서 initState가 아니라 여기서
  // 한 번만 요청한다.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested) return;
    _requested = true;
    unawaited(_load(MediaQuery.sizeOf(context).width.truncate()));
  }

  Future<void> _load(int width) async {
    if (!Ads.bannerEnabled) return;
    try {
      // 이 게임은 가로로 고정돼 있다. 가로 기준 띠는 세로보다 낮아서(보통
      // 32dp) 월드 카드에서 뺏는 높이가 적다.
      final size =
          await AdSize.getLargeAnchoredAdaptiveBannerAdSizeWithOrientation(
            Orientation.landscape,
            width,
          );
      if (size == null || !mounted) return;
      final ad = BannerAd(
        size: size,
        adUnitId: Ads.bannerUnitId,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            if (!mounted) {
              ad.dispose();
              return;
            }
            setState(() => _ad = ad as BannerAd);
          },
          onAdFailedToLoad: (ad, _) => ad.dispose(),
        ),
      );
      await ad.load();
    } catch (_) {
      // 광고 없이 홈 화면만 보여 준다.
    }
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (ad == null) return const SizedBox.shrink();
    return SizedBox(
      width: ad.size.width.toDouble(),
      height: ad.size.height.toDouble(),
      child: AdWidget(ad: ad),
    );
  }
}
