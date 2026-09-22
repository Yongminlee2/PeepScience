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
  const AdBanner({super.key, this.maxWidth, this.compact = false});

  /// 띠에 내줄 너비 상한(논리 픽셀). 띠 높이는 너비에서 정해지므로, 좁게
  /// 잡으면 낮은 띠가 온다. 게임 화면처럼 세로 한 줄이 아까운 곳에서 쓴다.
  final double? maxWidth;

  /// 낮은 띠(가로 기준 32)를 쓴다. 게임 화면처럼 세로 한 줄이 판 크기를
  /// 그대로 깎는 곳에서 켠다 - 큰 띠는 60이라 판이 두 배로 작아진다.
  final bool compact;

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
    var width = MediaQuery.sizeOf(context).width;
    final cap = widget.maxWidth;
    if (cap != null && cap < width) width = cap;
    unawaited(_load(width.truncate()));
  }

  Future<void> _load(int width) async {
    await Ads.initialized;
    if (!mounted || !Ads.bannerEnabled) return;
    try {
      // 이 게임은 가로로 고정돼 있다. 가로 기준 띠는 세로보다 낮아서(보통
      // 32dp) 월드 카드에서 뺏는 높이가 적다.
      final size = widget.compact
          // ignore: deprecated_member_use - 낮은 띠(32)를 주는 건 이 쪽뿐이다.
          ? await AdSize.getAnchoredAdaptiveBannerAdSize(
              Orientation.landscape,
              width,
            )
          : await AdSize.getLargeAnchoredAdaptiveBannerAdSizeWithOrientation(
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
