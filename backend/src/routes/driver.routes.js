const router = require('express').Router();
const { requireAuth, requireRole } = require('../middleware/auth');
const { setOnline, setOffline, updateLocation } = require('../controllers/driverController');

router.post('/online', requireAuth, requireRole('driver'), setOnline);
router.post('/offline', requireAuth, requireRole('driver'), setOffline);
router.post('/location', requireAuth, requireRole('driver'), updateLocation);

module.exports = router;
