import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'api/driver_api.dart';

/// Foreground location pinger. The rider app's matching engine uses a
/// 2dsphere index on `Driver.currentLocation` to find nearby drivers; for
/// that to work this app has to keep posting `{lat, lng}` to
/// `POST /drivers/location` while the driver is online.
///
/// **Foreground only.** We deliberately don't request the BACKGROUND
/// location permission — too aggressive for V1, and Apple/Google review
/// teams ask for serious justification before approving it. While the
/// app is in the background, the OS pauses our ticker; on resume we
/// start pinging again.
///
/// Lifecycle:
///   - HomeScreen calls [start] on a successful "Go online" toggle.
///   - HomeScreen calls [stop] on "Go offline" or sign-out.
///   - SplashScreen calls [start] if the user lands on home with
///     `profile.isOnline == true` (resume after relaunch).
///
/// [start] and [stop] are idempotent — calling start while already
/// running is a no-op, calling stop while already stopped is a no-op.
class LocationPushService extends ChangeNotifier {
  /// Tick interval. 20s is the rider app's expected freshness window for
  /// the "your driver is 4 min away" UI without burning battery.
  static const Duration tickInterval = Duration(seconds: 20);

  final DriverApi _api;

  Timer? _ticker;
  bool _running = false;
  String? _lastError;
  DateTime? _lastSuccessAt;

  LocationPushService({required DriverApi api}) : _api = api;

  bool get running => _running;
  String? get lastError => _lastError;
  DateTime? get lastSuccessAt => _lastSuccessAt;

  /// Begin ticking. Requests location permission on first call. Safe to
  /// call repeatedly — a no-op when already running.
  Future<void> start() async {
    if (_running) return;
    final ok = await _ensurePermission();
    if (!ok) {
      _lastError = 'Location permission not granted';
      notifyListeners();
      return;
    }
    _running = true;
    _lastError = null;
    notifyListeners();
    // Fire one immediately so the backend sees a fresh location right
    // after the toggle. Future ticks happen on the timer.
    unawaited(_pingOnce());
    _ticker = Timer.periodic(tickInterval, (_) => _pingOnce());
  }

  /// Stop ticking. Safe to call when already stopped.
  void stop() {
    if (!_running) return;
    _ticker?.cancel();
    _ticker = null;
    _running = false;
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }

  /// Requests `whileInUse` and returns whether we got it. Logs and
  /// returns false on denied/permanently-denied — the caller surfaces
  /// the failure via [lastError] without throwing, so a permission
  /// denial doesn't crash the toggle flow.
  Future<bool> _ensurePermission() async {
    final serviceOn = await Geolocator.isLocationServiceEnabled();
    if (!serviceOn) {
      debugPrint('[location] OS location services are disabled');
      return false;
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p == LocationPermission.denied ||
        p == LocationPermission.deniedForever) {
      debugPrint('[location] permission denied: $p');
      return false;
    }
    return true;
  }

  Future<void> _pingOnce() async {
    if (!_running) return;
    try {
      // medium accuracy is plenty for the matching engine's km-scale
      // radius queries. `best` would drain battery for no win. Time limit
      // caps each call so a wedged GPS fix doesn't pile up requests.
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 10),
      );
      await _api.updateLocation(lat: pos.latitude, lng: pos.longitude);
      _lastSuccessAt = DateTime.now();
      if (_lastError != null) {
        _lastError = null;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[location] ping failed: $e');
      _lastError = e.toString();
      notifyListeners();
      // Don't tear down the ticker on a single failure — transient GPS
      // unavailability is normal. We'll try again next tick.
    }
  }
}
