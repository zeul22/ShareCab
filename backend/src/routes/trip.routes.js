const router = require('express').Router();
const { requireAuth, requireRole } = require('../middleware/auth');
const ctrl = require('../controllers/tripController');

router.post('/estimate', requireAuth, ctrl.estimate);
router.post('/', requireAuth, ctrl.requestTrip);
router.get('/mine', requireAuth, ctrl.listMyTrips);
// /mine/active must be declared before /:id so Express doesn't treat "active"
// as a trip id and 404 it.
router.get('/mine/active', requireAuth, ctrl.getMyActiveTrip);
router.get('/:id', requireAuth, ctrl.getTrip);
router.post('/:id/cancel', requireAuth, ctrl.cancelTrip);
router.get('/groups/:id/fare', requireAuth, ctrl.getGroupFare);

// Driver-only lifecycle transitions.
router.post('/:id/arrive', requireAuth, requireRole('driver'), ctrl.arriveTrip);
// Per-rider lifecycle. The driver hits these once per stop (the app's
// geofence banner surfaces the right rider). Replaces the old bulk
// /start + /complete which couldn't represent a partially-loaded cab.
router.post('/:id/picked-up', requireAuth, requireRole('driver'), ctrl.pickUpRider);
router.post('/:id/dropped', requireAuth, requireRole('driver'), ctrl.dropOffRider);

module.exports = router;
