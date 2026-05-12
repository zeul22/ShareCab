const router = require('express').Router();
const { requireAuth, requireRole } = require('../middleware/auth');
const {
  setOnline,
  setOffline,
  updateLocation,
  getMyDriver,
  getMyDispatch,
  getMySubscription,
  startSubscriptionOrder,
  confirmSubscription,
  onboardDriver,
  getMyOffer,
  acceptOffer,
  rejectOffer,
} = require('../controllers/driverController');

// Driver-app onboarding wizard target. Requires a valid session but NOT
// the 'driver' role — at this point the user is still a rider promoting
// themselves. The controller flips role + creates the Driver doc.
router.post('/onboard', requireAuth, onboardDriver);

router.post('/online', requireAuth, requireRole('driver'), setOnline);
router.post('/offline', requireAuth, requireRole('driver'), setOffline);
router.post('/location', requireAuth, requireRole('driver'), updateLocation);

// One-shot snapshot for the driver-home screen. NOT role-gated: the
// driver app calls this immediately after OTP login to decide whether
// to route to onboarding (no Driver doc → 404), the pending-review
// screen (status=pending), or home (status=approved). At that point
// the user may still be role=rider, so a `requireRole('driver')` gate
// would block onboarding entirely. The controller still scopes to
// `Driver.findOne({ user: req.auth.userId })`, so a user can only ever
// see their own record — no information leak from dropping the gate.
router.get('/me', requireAuth, getMyDriver);

// Currently-dispatched trip(s) for the requesting driver. Empty list when
// they're online but unassigned; the client polls this on a tick.
router.get('/me/dispatch', requireAuth, requireRole('driver'), getMyDispatch);

// Pending offer for the driver's IncomingOfferSheet. 204 when no offer
// is outstanding — cheap polling signal at 3s cadence on the home screen.
router.get('/me/offer', requireAuth, requireRole('driver'), getMyOffer);

// Accept / reject lifecycle on a specific offered trip. Backend's
// dispatchService handles state transitions + re-dispatch on reject.
router.post('/offers/:tripId/accept', requireAuth, requireRole('driver'), acceptOffer);
router.post('/offers/:tripId/reject', requireAuth, requireRole('driver'), rejectOffer);

// Subscription lifecycle. /me/subscription must be declared before any
// param-rich routes so Express doesn't accidentally route 'me' as an id.
router.get('/me/subscription', requireAuth, requireRole('driver'), getMySubscription);
router.post('/subscribe', requireAuth, requireRole('driver'), startSubscriptionOrder);
router.post('/subscribe/confirm', requireAuth, requireRole('driver'), confirmSubscription);

module.exports = router;
