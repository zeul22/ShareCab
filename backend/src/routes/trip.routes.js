const router = require('express').Router();
const { requireAuth, requireRole } = require('../middleware/auth');
const ctrl = require('../controllers/tripController');

router.post('/estimate', requireAuth, ctrl.estimate);
router.post('/', requireAuth, ctrl.requestTrip);
router.get('/mine', requireAuth, ctrl.listMyTrips);
router.get('/:id', requireAuth, ctrl.getTrip);
router.post('/:id/cancel', requireAuth, ctrl.cancelTrip);
router.get('/groups/:id/fare', requireAuth, ctrl.getGroupFare);

// Driver-only lifecycle transitions.
router.post('/:id/arrive', requireAuth, requireRole('driver'), ctrl.arriveTrip);
router.post('/:id/start', requireAuth, requireRole('driver'), ctrl.startTrip);
router.post('/:id/complete', requireAuth, requireRole('driver'), ctrl.completeTrip);

module.exports = router;
