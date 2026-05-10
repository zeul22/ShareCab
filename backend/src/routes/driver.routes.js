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
} = require('../controllers/driverController');

router.post('/online', requireAuth, requireRole('driver'), setOnline);
router.post('/offline', requireAuth, requireRole('driver'), setOffline);
router.post('/location', requireAuth, requireRole('driver'), updateLocation);

// One-shot snapshot for the driver-home screen.
router.get('/me', requireAuth, requireRole('driver'), getMyDriver);

// Currently-dispatched trip(s) for the requesting driver. Empty list when
// they're online but unassigned; the client polls this on a tick.
router.get('/me/dispatch', requireAuth, requireRole('driver'), getMyDispatch);

// Subscription lifecycle. /me/subscription must be declared before any
// param-rich routes so Express doesn't accidentally route 'me' as an id.
router.get('/me/subscription', requireAuth, requireRole('driver'), getMySubscription);
router.post('/subscribe', requireAuth, requireRole('driver'), startSubscriptionOrder);
router.post('/subscribe/confirm', requireAuth, requireRole('driver'), confirmSubscription);

module.exports = router;
