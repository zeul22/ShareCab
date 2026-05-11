import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/luggage.dart';
import '../models/match_proposal.dart';
import '../models/payment.dart';
import '../models/place.dart';
import '../models/ride.dart';
import '../models/ride_search.dart';
import '../models/vehicle.dart';
import '../routes.dart';
import 'api/mock_ride_api.dart';
import 'api/ride_api.dart';
import 'notification_service.dart';

/// Holds the in-progress booking flow across screens.
///
/// State machine (high-level):
///
///   idle ──► planning ──► searching ──► proposing
///                            │              │ accept
///                            │              ▼
///                            │         confirmed (Ride created)
///                            │              │
///                            │              ▼
///                            │           inRide
///                            │              │ complete
///                            │              ▼
///                            │           paying
///                            │              │
///                            │              ▼
///                            │           completed
///                            │ reject
///                            ▼
///                         searching (again)
///
/// Screens read from this; user actions call its methods.
enum FlowStage {
  idle,
  planning,
  searching,
  proposing,
  confirmed,
  inRide,
  paying,
  completed,
}

class RideFlowState extends ChangeNotifier {
  final RideApi _api;

  RideFlowState(this._api);

  FlowStage _stage = FlowStage.idle;
  RideSearch _search = RideSearch(startedAt: DateTime.now());
  String? _sessionId;
  List<MatchProposal> _proposals = const [];
  MatchProposal? _selectedProposal;
  Ride? _activeRide;
  Payment? _activePayment;
  String? _error;

  // Polling: keeps the active proposal/ride in sync with backend state so the
  // app sees co-rider drops (the other rider rejected) and external cancels.
  Timer? _watchTimer;
  String? _watchedTripId;
  int _lastKnownRiderCount = 0;
  String? _toastMessage;

  // When the rider hit "Find a match". Used to compute the remaining slice
  // of the 5-minute search window when SearchingScreen rebuilds — so the
  // progress bar resumes accurately if the user navigated away and back.
  DateTime? _searchStartedAt;

  // Set true when the polling watcher sees the rider lose ALL their
  // co-riders (newCount drops to 1). The active-ride screens watch this
  // and pop a "wait for another rider OR continue solo" dialog. One-shot:
  // cleared the moment a screen consumes it (see clearCoRiderLost).
  bool _coRiderLostPending = false;

  FlowStage get stage => _stage;
  RideSearch get search => _search;
  List<MatchProposal> get proposals => _proposals;
  MatchProposal? get selectedProposal => _selectedProposal;
  Ride? get activeRide => _activeRide;
  Payment? get activePayment => _activePayment;
  String? get error => _error;
  String? get toastMessage => _toastMessage;
  DateTime? get searchStartedAt => _searchStartedAt;
  bool get coRiderLostPending => _coRiderLostPending;

  // ---------------------------------------------------------------------------
  // Search building
  // ---------------------------------------------------------------------------

  void resetForNewSearch() {
    _stage = FlowStage.planning;
    _search = RideSearch(startedAt: DateTime.now());
    _sessionId = null;
    _proposals = const [];
    _selectedProposal = null;
    _activeRide = null;
    _activePayment = null;
    _error = null;
    notifyListeners();
  }

  void setPickup(Place pickup) {
    _ensurePlanning();
    _search = _search.copyWith(pickup: pickup);
    notifyListeners();
  }

  void setDropoff(Place dropoff) {
    _ensurePlanning();
    _search = _search.copyWith(dropoff: dropoff);
    notifyListeners();
  }

  void setLuggage(LuggageProfile luggage) {
    _ensurePlanning();
    _search = _search.copyWith(luggage: luggage);
    notifyListeners();
  }

  void setPreference(MatchPreference pref) {
    _ensurePlanning();
    _search = _search.copyWith(preference: pref);
    notifyListeners();
  }

  void setPreferredVehicle(VehicleType? vehicle) {
    _ensurePlanning();
    _search = _search.copyWith(
      preferredVehicle: vehicle,
      clearPreferredVehicle: vehicle == null,
    );
    notifyListeners();
  }

  void setAirportMode({required bool enabled, DateTime? landsAt}) {
    _ensurePlanning();
    _search = _search.copyWith(
      airportArrivalMode: enabled,
      airportLandsAt: landsAt,
      clearAirportLandsAt: !enabled,
    );
    notifyListeners();
  }

  void _ensurePlanning() {
    if (_stage == FlowStage.idle) _stage = FlowStage.planning;
  }

  // ---------------------------------------------------------------------------
  // Searching
  // ---------------------------------------------------------------------------

  Future<void> startSearch() async {
    if (!_search.isReadyToSearch) {
      _error = 'Pick both a pickup and a destination first';
      notifyListeners();
      return;
    }
    _stage = FlowStage.searching;
    _proposals = const [];
    _selectedProposal = null;
    _error = null;
    _searchStartedAt = DateTime.now();
    notifyListeners();

    try {
      _sessionId = await _api.createSearchSession(_search);
      final proposals = _search.preference == MatchPreference.randomCompatible
          ? await _api.findRandomMatches(_sessionId!, _search)
          : await _api.findDestinationMatches(_sessionId!, _search);
      _proposals = proposals;

      // findDestinationMatches now always returns one proposal:
      //   - riderCount >= 2  → matched at trip-create time, advance immediately
      //   - riderCount == 1  → still pending; we stay in `searching` and let
      //                        the polling watcher transition us to
      //                        `proposing` when a co-rider joins.
      final matchedNow =
          proposals.isNotEmpty && proposals.first.riderCount >= 2;
      _stage = matchedNow ? FlowStage.proposing : FlowStage.searching;

      if (matchedNow) {
        // Notify on the immediate match. Background-app-not-killed case is
        // covered by the system notification; app-fully-killed needs FCM
        // (see docs/notifications.md).
        final p = proposals.first;
        final coRiders = p.coPassengers.length;
        NotificationService.instance.matchFound(
          coRiderText: coRiders == 0
              ? 'Riding solo'
              : '$coRiders co-rider${coRiders == 1 ? '' : 's'}',
          perRiderFare: p.perRiderFare,
        );
      } else if (proposals.isNotEmpty) {
        // Pending — start watching the trip so the SearchingScreen learns
        // the moment a co-rider pairs up with us.
        startWatching();
      }
    } catch (e) {
      _error = e.toString();
      _stage = FlowStage.planning;
    }
    notifyListeners();
  }

  /// Mark the co-rider-lost prompt as handled. Screens call this the moment
  /// they show the dialog so a subsequent rebuild doesn't re-trigger it.
  /// Idempotent.
  void clearCoRiderLost() {
    if (!_coRiderLostPending) return;
    _coRiderLostPending = false;
    notifyListeners();
  }

  /// Stay in the current trip as a solo ride. Trip remains `driver_assigned`
  /// (or whatever post-accept stage it was in), the matchGroup just has one
  /// trip now, fare auto-adjusts to full solo via `_buildProposalFromTrip`.
  /// Pure local-state op — no backend call needed.
  void continueSolo() {
    _coRiderLostPending = false;
    // Force a refresh so the screen rebuilds with the updated rider count
    // immediately rather than waiting for the next 2s poll tick.
    notifyListeners();
  }

  /// Cancel the current (now-solo) trip and start a fresh search for a new
  /// co-rider. Reuses retrySearch's cancel-then-create logic.
  Future<void> searchForAnother() async {
    _coRiderLostPending = false;
    await retrySearch();
  }

  /// Cancel an in-flight trip — works for any post-accept state
  /// (`confirmed` / `arriving` / `in_progress`) as well as a pending search.
  /// Used by the cancel buttons on RideConfirmationScreen and
  /// RideStatusScreen so the rider can back out even after accepting.
  ///
  /// Returns true if a cancellation went through, false if there was nothing
  /// to cancel.
  Future<bool> cancelActiveRide() async {
    final tripId = _activeRide?.id ??
        (_proposals.isNotEmpty ? _proposals.first.id : null);
    if (tripId == null) return false;

    final proposal = _proposals.isNotEmpty
        ? _proposals.first
        : MatchProposal(
            id: tripId,
            coPassengers: const [],
            stops: const [],
            vehicleType: VehicleType.sedan,
            groupFare: 0,
            perRiderFare: 0,
            distanceKm: 0,
            durationMin: 0,
            luggageSeatsUsed: 0,
            luggageSeatsFree: 0,
          );

    stopWatching();
    try {
      await _api.rejectMatch(_sessionId ?? 'cancel', proposal);
    } catch (_) {
      // Best-effort — backend may auto-cancel via the deferred timer.
    }

    // Always reset local state so the home screen + banner stop showing
    // a stale active ride.
    _stage = FlowStage.idle;
    _activeRide = null;
    _selectedProposal = null;
    _proposals = const [];
    _searchStartedAt = null;
    _activePayment = null;
    _error = null;
    notifyListeners();
    return true;
  }

  /// Cancel the current trip (if any) and start a fresh search. Used by the
  /// "Search again" button on the empty-state UI so we don't leave orphaned
  /// `requested` trips on the backend.
  Future<void> retrySearch() async {
    final currentTripId =
        _proposals.isNotEmpty ? _proposals.first.id : _activeRide?.id;
    stopWatching();
    if (currentTripId != null) {
      try {
        await _api.rejectMatch(_sessionId ?? 'retry', _proposals.isNotEmpty
            ? _proposals.first
            : MatchProposal(
                id: currentTripId,
                coPassengers: const [],
                stops: const [],
                vehicleType: VehicleType.sedan,
                groupFare: 0,
                perRiderFare: 0,
                distanceKm: 0,
                durationMin: 0,
                luggageSeatsUsed: 0,
                luggageSeatsFree: 0,
              ));
      } catch (_) {
        // Cancel best-effort — a stale trip on backend isn't a hard blocker.
      }
    }
    return startSearch();
  }

  // ---------------------------------------------------------------------------
  // Cold-start restore
  //
  // Called from the splash screen once auth is bootstrapped. Asks the backend
  // for any in-flight trip the rider has and rehydrates the flow into the
  // appropriate stage so the splash router can drop the user back where they
  // left off (search results, ride confirmation, live ride, etc.).
  // Returns the resume route (one of Routes.*) or null if there's nothing
  // to restore.
  // ---------------------------------------------------------------------------
  Future<String?> restoreActiveRide() async {
    try {
      final ride = await _api.getActiveRide();
      if (ride == null) return null;

      _activeRide = ride;
      _selectedProposal = ride.proposal;
      _proposals = [ride.proposal];
      _sessionId = 'restored_${ride.id}';
      _search = RideSearch(
        pickup: ride.proposal.stops.first.place,
        dropoff: ride.proposal.stops.last.place,
        startedAt: DateTime.now(),
      );

      // Rider-only mode signal: the restored ride has no driver
      // assigned. All non-terminal restores land on the coordination
      // screen instead of the driver-tracking flow, so the rider
      // returns to the same UI they left.
      final isRiderOnly = ride.driver.id.isEmpty;

      // Map ride status → flow stage → resume route. Resume polling for
      // any non-terminal status so the banner / screens keep getting fresh
      // state (driver progress, completion events, co-rider drops, etc).
      switch (ride.status) {
        case RideStatus.confirmed:
          _stage = FlowStage.confirmed;
          startWatching();
          notifyListeners();
          return isRiderOnly
              ? Routes.riderCoordination
              : Routes.rideConfirmation;
        case RideStatus.arriving:
        case RideStatus.inProgress:
          _stage = FlowStage.inRide;
          startWatching();
          notifyListeners();
          return isRiderOnly ? Routes.riderCoordination : Routes.liveRide;
        case RideStatus.completed:
          _stage = FlowStage.paying;
          notifyListeners();
          return Routes.payment;
        case RideStatus.cancelled:
          // Treat cancelled as "nothing to restore."
          _activeRide = null;
          _proposals = const [];
          _selectedProposal = null;
          notifyListeners();
          return null;
      }
    } catch (_) {
      // Network/parse errors on cold start shouldn't block app launch.
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Match acceptance
  // ---------------------------------------------------------------------------

  Future<void> acceptProposal(MatchProposal proposal) async {
    if (_sessionId == null) return;
    _selectedProposal = proposal;
    _error = null;
    notifyListeners();

    try {
      final ride = await _api.acceptMatch(_sessionId!, proposal);
      _activeRide = ride;
      _stage = FlowStage.confirmed;
    } catch (e) {
      _error = e.toString();
    }
    notifyListeners();
  }

  Future<void> rejectProposal(MatchProposal proposal) async {
    if (_sessionId == null) return;
    await _api.rejectMatch(_sessionId!, proposal);
    _proposals = _proposals.where((p) => p.id != proposal.id).toList();
    if (_proposals.isEmpty) {
      _stage = FlowStage.searching;
    }
    stopWatching();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Live state polling
  //
  // Screens that show match/confirmation state (MatchResultScreen,
  // RideConfirmationScreen) call startWatching() in initState and
  // stopWatching() in dispose. Every 2s we re-fetch the trip and update
  // the proposal / active ride. If the rider count changes (the other
  // rider rejected) or the trip becomes cancelled, we surface a toast
  // and let the screens react.
  // ---------------------------------------------------------------------------

  /// Begin polling the current proposal / active ride. Idempotent.
  void startWatching() {
    final id = _activeRide?.id ??
        (_proposals.isNotEmpty ? _proposals.first.id : null);
    if (id == null) return;
    if (_watchTimer != null && _watchedTripId == id) return;

    _watchTimer?.cancel();
    _watchedTripId = id;
    _lastKnownRiderCount =
        _activeRide?.proposal.riderCount ?? _proposals.first.riderCount;
    _watchTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _refreshWatched(),
    );
  }

  void stopWatching() {
    _watchTimer?.cancel();
    _watchTimer = null;
    _watchedTripId = null;
  }

  /// Screens consume the toast and call this once they've shown it.
  void clearToast() {
    _toastMessage = null;
  }

  Future<void> _refreshWatched() async {
    final id = _watchedTripId;
    if (id == null) return;
    try {
      final ride = await _api.getLiveRide(id);
      final newCount = ride.proposal.riderCount;
      bool changed = false;

      // Trip cancelled (admin / driver / external / search-window-expiry).
      if (ride.status == RideStatus.cancelled) {
        if (_stage == FlowStage.searching) {
          // Backend's 5-min window expired. Fire the system notification
          // here — the user may have navigated away from SearchingScreen
          // (banner-driven workflow), so the screen-level _onProgressDone
          // wouldn't fire. NotificationService is idempotent on the same
          // channel id, so this won't double-up if the screen also fires.
          NotificationService.instance.searchTimedOut();
        } else {
          _toastMessage = 'This match was cancelled.';
        }
        stopWatching();
        _activeRide = null;
        _proposals = const [];
        _selectedProposal = null;
        _searchStartedAt = null;
        _stage = FlowStage.planning;
        notifyListeners();
        return;
      }

      // Co-rider count dropped — refresh proposal/ride so fare reflects the
      // new group size, then either prompt the rider for a decision (if they
      // lost ALL their co-riders) or just toast (if some are still around).
      if (newCount < _lastKnownRiderCount) {
        if (newCount == 1) {
          // Group is now solo — surface the wait-vs-solo dialog on the
          // active-ride screens. Suppress the toast; the dialog is the
          // primary surface for this state.
          _coRiderLostPending = true;
        } else {
          _toastMessage =
              'A co-rider cancelled — ${newCount - 1} co-rider(s) left.';
        }
        changed = true;
      } else if (newCount > _lastKnownRiderCount) {
        // A new rider joined. If we were in the searching stage waiting for
        // our first co-rider, this is the match — advance to `proposing` so
        // the SearchingScreen can hand off to MatchResult, and fire the
        // match-found system notification.
        if (_stage == FlowStage.searching && newCount >= 2) {
          _stage = FlowStage.proposing;
          NotificationService.instance.matchFound(
            coRiderText: '${newCount - 1} co-rider${newCount == 2 ? '' : 's'}',
            perRiderFare: ride.proposal.perRiderFare,
          );
        } else {
          _toastMessage = 'A new co-rider joined the group.';
        }
        changed = true;
      }
      _lastKnownRiderCount = newCount;

      // Always sync state — even if rider count unchanged, status (driver
      // arriving, in_progress, etc.) might have advanced.
      if (_activeRide != null) {
        _activeRide = ride;
        changed = true;
      }
      if (_proposals.isNotEmpty) {
        _proposals = [ride.proposal];
        if (_selectedProposal != null) _selectedProposal = ride.proposal;
        changed = true;
      }
      if (changed) notifyListeners();
    } catch (_) {
      // Transient network errors during polling shouldn't disrupt the UI.
    }
  }

  @override
  void dispose() {
    stopWatching();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // OTP / live ride / completion
  // ---------------------------------------------------------------------------

  Future<bool> verifyOtp(String otp) async {
    final ride = _activeRide;
    if (ride == null) return false;
    try {
      _activeRide = await _api.verifyOtp(ride.id, otp);
      _stage = FlowStage.inRide;
      _error = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Wrong OTP. Ask the driver to check.';
      notifyListeners();
      return false;
    }
  }

  Future<void> markRideComplete() async {
    // Real backend pushes completion via socket; the mock exposes a side-channel.
    final api = _api;
    if (api is MockRideApi) {
      _activeRide = await api.completeActiveRide();
      _stage = FlowStage.paying;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Payment
  // ---------------------------------------------------------------------------

  void preparePayment({required PaymentTiming timing, required PaymentMethod method}) {
    final ride = _activeRide;
    if (ride == null) return;
    _activePayment = Payment(
      id: 'pay_${DateTime.now().microsecondsSinceEpoch}',
      rideId: ride.id,
      riderUserId: 'self',
      amount: ride.perRiderFare,
      timing: timing,
      method: method,
      status: PaymentStatus.pending,
      createdAt: DateTime.now(),
    );
    notifyListeners();
  }

  Future<void> completePayment() async {
    final p = _activePayment;
    if (p == null) return;
    _activePayment = await _api.completePayment(p);
    _stage = FlowStage.completed;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // History
  // ---------------------------------------------------------------------------

  Future<List<Ride>> loadHistory() => _api.getRideHistory();

  /// Local-only reset after the trip has already been closed server-side
  /// (e.g. by the rider-only coordination screen's "We're done" button).
  /// Skips the best-effort backend cancel that [clear] does — we don't
  /// want to reject a trip that's already in `completed` state.
  void clearAfterClose() {
    stopWatching();
    _stage = FlowStage.idle;
    _search = RideSearch(startedAt: DateTime.now());
    _sessionId = null;
    _proposals = const [];
    _selectedProposal = null;
    _activeRide = null;
    _activePayment = null;
    _error = null;
    _searchStartedAt = null;
    notifyListeners();
  }

  /// Reset to idle. If there's a `requested` / `matched` trip still alive on
  /// the backend (user hit the X-button mid-search), best-effort cancel it
  /// so we don't leak orphans that other riders' matching could pick up.
  Future<void> clear() async {
    final lingeringTripId =
        _proposals.isNotEmpty ? _proposals.first.id : _activeRide?.id;
    stopWatching();
    _stage = FlowStage.idle;
    _search = RideSearch(startedAt: DateTime.now());
    _sessionId = null;
    _proposals = const [];
    _selectedProposal = null;
    _activeRide = null;
    _activePayment = null;
    _error = null;
    _searchStartedAt = null;
    notifyListeners();

    if (lingeringTripId != null) {
      try {
        await _api.rejectMatch('clear', MatchProposal(
          id: lingeringTripId,
          coPassengers: const [],
          stops: const [],
          vehicleType: VehicleType.sedan,
          groupFare: 0,
          perRiderFare: 0,
          distanceKm: 0,
          durationMin: 0,
          luggageSeatsUsed: 0,
          luggageSeatsFree: 0,
        ));
      } catch (_) {
        // Best-effort — a stranded backend trip is recoverable via the
        // backend's own deferred-cancel timer.
      }
    }
  }
}

