import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/driver_live_location.dart';
import 'api/ride_api.dart';

/// Polls the backend for the assigned driver's live position + ETA, and
/// notifies listeners so the rider's live-ride screen can re-render the
/// driver marker + ETA chip.
///
/// Cadence is 5 seconds — matches the driver app's fast-mode location push,
/// so the rider perceives ≤10s of staleness. The service is idempotent on
/// [start] / [stop]; switching trips re-targets the same timer.
class TripTrackingService extends ChangeNotifier {
  static const Duration pollInterval = Duration(seconds: 5);

  final RideApi _api;

  Timer? _poll;
  String? _tripId;
  DriverLiveLocation? _driverLocation;
  TripEta? _eta;
  String? _lastError;

  TripTrackingService(this._api);

  DriverLiveLocation? get driverLocation => _driverLocation;
  TripEta? get eta => _eta;
  String? get lastError => _lastError;
  bool get isTracking => _poll != null;

  /// Start (or re-target) polling for the given trip id. Cheap to call
  /// repeatedly with the same id; will swap target without dropping a tick
  /// when called with a new id.
  Future<void> start(String tripId) async {
    if (_tripId == tripId && _poll != null) return;
    _tripId = tripId;
    _driverLocation = null;
    _eta = null;
    _lastError = null;
    notifyListeners();
    // Fire once immediately so the screen doesn't wait 5s for the first
    // marker, then settle into the periodic cadence.
    unawaited(_tick());
    _poll?.cancel();
    _poll = Timer.periodic(pollInterval, (_) => _tick());
  }

  void stop() {
    _poll?.cancel();
    _poll = null;
    _tripId = null;
    _driverLocation = null;
    _eta = null;
    _lastError = null;
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }

  Future<void> _tick() async {
    final id = _tripId;
    if (id == null) return;
    try {
      final res = await _api.getDriverLocation(id);
      // Guard against late ticks landing after stop() — only commit when
      // we're still tracking the same trip.
      if (_tripId != id) return;
      _driverLocation = res.driver;
      _eta = res.eta;
      if (_lastError != null) _lastError = null;
      notifyListeners();
    } catch (e) {
      // 404 here is the normal "no driver assigned yet" or "driver
      // hasn't pinged yet" path — log + keep polling, don't surface a
      // user-visible error. Other failures get surfaced via lastError so
      // the screen can show "tracking paused" if it wants.
      final msg = e.toString();
      if (msg.contains('404') ||
          msg.contains('No driver assigned') ||
          msg.contains("hasn't reported")) {
        // Quiet — the rider's other UI already says "Looking for driver…"
        return;
      }
      if (kDebugMode) {
        debugPrint('[trip-track] tick failed: $msg');
      }
      _lastError = msg;
      notifyListeners();
    }
  }
}
