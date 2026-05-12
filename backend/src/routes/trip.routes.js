const router = require('express').Router();
const { requireAuth, requireRole } = require('../middleware/auth');
const ctrl = require('../controllers/tripController');

router.post('/estimate', requireAuth, ctrl.estimate);
router.post('/', requireAuth, ctrl.requestTrip);
router.get('/mine', requireAuth, ctrl.listMyTrips);
// /mine/active must be declared before /:id so Express doesn't treat "active"
// as a trip id and 404 it. Same rule for /destinations/recent below.
router.get('/mine/active', requireAuth, ctrl.getMyActiveTrip);
// Recent unique destinations the rider has dropped at. Powers the
// "tap to repeat a past trip" shortcut on the destination screen.
router.get('/destinations/recent', requireAuth, ctrl.getRecentDestinations);
router.get('/:id', requireAuth, ctrl.getTrip);
// Live driver position + ETA for the rider's map. Polled every 5s from
// the rider's RideStatusScreen while the trip is arriving / in_progress.
router.get('/:id/driver-location', requireAuth, ctrl.getDriverLocation);
router.post('/:id/cancel', requireAuth, ctrl.cancelTrip);
// Rider-only mode: consume an unlock to reveal co-rider details for
// this matched trip. No-op (returns 409) in driver-dispatch mode since
// matches in that mode aren't gated this way.
router.post('/:id/unlock-match', requireAuth, ctrl.unlockMatch);
// Rider taps "Find Cab" to commit to dispatch. In a shared trip both
// riders must hit this before any driver is offered; solo trips skip
// the gate entirely (readyToFindCab is set at trip creation).
router.post('/:id/find-cab', requireAuth, ctrl.findCab);
// Rider-only mode: rider self-closes a matched trip after they've
// coordinated their own cab off-platform. 409 in driver-dispatch mode.
router.post('/:id/rider-close', requireAuth, ctrl.riderCloseTrip);
// Rider-initiated "stop here" while in_progress. Charges the full
// pre-quoted fare (no proration). Distinct from /cancel (pre-pickup,
// no charge) and /rider-close (rider-only mode, no driver, fare=0).
router.post('/:id/end-early', requireAuth, ctrl.endRideEarly);
router.get('/groups/:id/fare', requireAuth, ctrl.getGroupFare);

// Driver-only lifecycle transitions.
router.post('/:id/arrive', requireAuth, requireRole('driver'), ctrl.arriveTrip);
// Per-rider lifecycle. The driver hits these once per stop (the app's
// geofence banner surfaces the right rider). Replaces the old bulk
// /start + /complete which couldn't represent a partially-loaded cab.
router.post('/:id/picked-up', requireAuth, requireRole('driver'), ctrl.pickUpRider);
router.post('/:id/dropped', requireAuth, requireRole('driver'), ctrl.dropOffRider);

module.exports = router;
