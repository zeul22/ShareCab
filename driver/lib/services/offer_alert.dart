import 'dart:async';

import 'package:flutter/services.dart';

/// Audible + tactile alert when an incoming ride offer arrives. Plays a
/// 3-pulse pattern (beep + heavy haptic) over ~2 seconds so the driver
/// notices even if they're looking away from the phone.
///
/// Why this shape, not a single beep:
///   - Drivers see hundreds of phone notifications a day; a single
///     short beep blends into the noise.
///   - 3 pulses over 2s reads as "this is THE one" without being
///     annoying — same rhythm Uber/Ola use.
///
/// Why SystemSound + HapticFeedback (not a packaged MP3 / audioplayers):
///   - No new dependency, no asset to license, ships today.
///   - Caveat: SystemSound.alert respects iOS/Android silent mode.
///     A phone-on-silent driver only feels the haptic. For
///     bypass-silent priority sound, we'd need flutter_local_notifications
///     with a high-priority channel — follow-up when push lands.
class OfferAlert {
  OfferAlert._();

  /// Number of pulses in the alert pattern. 3 is enough to register as
  /// intentional; more starts to feel like spam.
  static const _pulses = 3;
  static const _pulseGap = Duration(milliseconds: 600);

  static final List<Timer> _pending = [];

  /// Fire the alert. Idempotent in the sense that calling it twice in
  /// rapid succession just stacks more pulses — caller should [stop]
  /// first if they want a clean restart.
  static void play() {
    // Pulse 0 fires immediately so the driver hears it the same tick
    // the sheet pops, not 600ms later.
    _pulse();
    for (var i = 1; i < _pulses; i++) {
      final t = Timer(_pulseGap * i, _pulse);
      _pending.add(t);
    }
  }

  /// Cancel any queued pulses. Called from the offer sheet's dispose so
  /// late pulses don't fire after the driver has accepted / rejected.
  static void stop() {
    for (final t in _pending) {
      t.cancel();
    }
    _pending.clear();
  }

  static void _pulse() {
    // SystemSound returns a Future but it fires the sound synchronously
    // through the platform channel — don't await; we want overlapping
    // sound + haptic to feel like one event.
    SystemSound.play(SystemSoundType.alert);
    HapticFeedback.heavyImpact();
  }
}
