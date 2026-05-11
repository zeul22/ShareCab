import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../utils/api_config.dart';

/// One-time outcome of showing a rewarded ad. Callers `switch` on the
/// sealed subtype rather than juggling success/error flags.
sealed class AdResult {
  const AdResult();
}

class AdRewardEarned extends AdResult {
  /// AdMob amount + type from the rewarded callback. We don't use them
  /// at the gate (one ad == one credit) but expose for telemetry.
  final num amount;
  final String type;
  const AdRewardEarned({required this.amount, required this.type});
}

class AdDismissed extends AdResult {
  /// User closed the ad before the reward callback fired (early dismiss).
  const AdDismissed();
}

class AdFailed extends AdResult {
  final String message;
  const AdFailed(this.message);
}

/// Thin wrapper around `google_mobile_ads` for the rewarded-video flow.
/// Keeps the unlock gate UI free of AdMob plumbing — call [init] once
/// at startup and [showRewardedAd] each time the rider watches one.
///
/// Pattern: load → show → wait for result → done. We don't pre-load
/// the next ad after a show (could be added if latency becomes an
/// issue, but ad-load latency is typically <1s on a warm connection).
class AdService {
  AdService._();
  static final AdService instance = AdService._();

  bool _initialised = false;
  String? _initErrorMessage;

  /// Whether ads are usable on this device. False before [init] runs,
  /// false after init if it failed. The unlock sheet checks this to
  /// hide the "Watch ads" CTA on devices where the SDK can't run
  /// (e.g. an Android emulator without Google Play Services).
  bool get isAvailable => _initialised;

  /// Human-readable explanation of why ads aren't working. Null when
  /// ads are available. Used by the unlock sheet's empty state.
  String? get unavailableReason => _initialised ? null : _initErrorMessage;

  /// Initialise the underlying SDK. Safe to call multiple times — only
  /// the first call hits the native side.
  Future<void> init() async {
    if (_initialised) return;
    try {
      await MobileAds.instance.initialize();
      _initialised = true;
      _initErrorMessage = null;
      debugPrint('[ads] MobileAds initialised');
    } catch (e) {
      // Init failure is non-fatal — the app keeps working, the unlock
      // gate just falls back to the pay path. Most common causes:
      //   1. New plugin added without `flutter clean` + reinstall —
      //      the native side never linked the SDK.
      //   2. Android emulator without Google Play Services (use a
      //      "Google Play" system image, not AOSP, in AVD Manager).
      //   3. Wrong / missing AdMob app id in AndroidManifest /
      //      Info.plist (we ship the official test id by default).
      _initErrorMessage = e.toString();
      debugPrint('[ads] MobileAds init failed: $e');
    }
  }

  /// The ad unit id to load. Resolves platform-specific dart-defines
  /// from [ApiConfig].
  String get _adUnitId =>
      ApiConfig.admobRewardedAdUnit(isIos: !kIsWeb && Platform.isIOS);

  /// Load + immediately show a rewarded ad. Returns the outcome —
  /// `AdRewardEarned` when AdMob fires the reward callback, otherwise
  /// `AdDismissed` (user bailed) or `AdFailed` (load error / SDK
  /// problem). Callers should treat anything other than reward-earned
  /// as a no-op (don't increment the ad counter).
  Future<AdResult> showRewardedAd() async {
    if (!_initialised) {
      await init();
      if (!_initialised) {
        return AdFailed(
          'Ads aren\'t available on this device. '
          'Use the pay option to unlock instead. '
          '(${_initErrorMessage ?? 'AdMob SDK failed to initialise'})',
        );
      }
    }

    final loaded = Completer<RewardedAd?>();
    try {
      await RewardedAd.load(
        adUnitId: _adUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: loaded.complete,
          onAdFailedToLoad: (err) {
            debugPrint('[ads] load failed: ${err.code} ${err.message}');
            loaded.complete(null);
          },
        ),
      );
    } catch (e) {
      debugPrint('[ads] load threw: $e');
      return AdFailed('Could not load ad: $e');
    }

    final ad = await loaded.future;
    if (ad == null) {
      return const AdFailed(
        'No ad available right now. Try again or pay to unlock.',
      );
    }

    final result = Completer<AdResult>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        // If the reward callback didn't fire first, the user dismissed
        // before the threshold. dispose order matters — we complete
        // here only if the reward callback hasn't already.
        if (!result.isCompleted) result.complete(const AdDismissed());
      },
      onAdFailedToShowFullScreenContent: (ad, err) {
        ad.dispose();
        if (!result.isCompleted) {
          result.complete(AdFailed('Ad failed to show: ${err.message}'));
        }
      },
    );

    await ad.show(
      onUserEarnedReward: (_, reward) {
        if (!result.isCompleted) {
          result.complete(AdRewardEarned(
            amount: reward.amount,
            type: reward.type,
          ));
        }
      },
    );

    return result.future;
  }
}
