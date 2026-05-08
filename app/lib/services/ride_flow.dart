import 'package:flutter/foundation.dart';

import '../models/luggage.dart';
import '../models/match_proposal.dart';
import '../models/payment.dart';
import '../models/place.dart';
import '../models/ride.dart';
import '../models/ride_search.dart';
import '../models/vehicle.dart';
import 'api/mock_ride_api.dart';
import 'api/ride_api.dart';

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

  FlowStage get stage => _stage;
  RideSearch get search => _search;
  List<MatchProposal> get proposals => _proposals;
  MatchProposal? get selectedProposal => _selectedProposal;
  Ride? get activeRide => _activeRide;
  Payment? get activePayment => _activePayment;
  String? get error => _error;

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
    notifyListeners();

    try {
      _sessionId = await _api.createSearchSession(_search);
      final proposals = _search.preference == MatchPreference.randomCompatible
          ? await _api.findRandomMatches(_sessionId!, _search)
          : await _api.findDestinationMatches(_sessionId!, _search);
      _proposals = proposals;
      _stage = proposals.isEmpty ? FlowStage.searching : FlowStage.proposing;
    } catch (e) {
      _error = e.toString();
      _stage = FlowStage.planning;
    }
    notifyListeners();
  }

  Future<void> retrySearch() => startSearch();

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
    notifyListeners();
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

  void clear() {
    _stage = FlowStage.idle;
    _search = RideSearch(startedAt: DateTime.now());
    _sessionId = null;
    _proposals = const [];
    _selectedProposal = null;
    _activeRide = null;
    _activePayment = null;
    _error = null;
    notifyListeners();
  }
}

