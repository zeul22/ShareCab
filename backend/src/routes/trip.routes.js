const router = require('express').Router();
const { requireAuth } = require('../middleware/auth');
const ctrl = require('../controllers/tripController');

router.post('/estimate', requireAuth, ctrl.estimate);
router.post('/', requireAuth, ctrl.requestTrip);
router.get('/mine', requireAuth, ctrl.listMyTrips);
router.get('/:id', requireAuth, ctrl.getTrip);
router.post('/:id/cancel', requireAuth, ctrl.cancelTrip);
router.get('/groups/:id/fare', requireAuth, ctrl.getGroupFare);

module.exports = router;
