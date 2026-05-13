const router = require('express').Router();
const { requireAuth } = require('../middleware/auth');
const ctrl = require('../controllers/geoController');

// Reverse-geocode coords → short place name. Used by the rider app's
// LocationService to label the captured pickup with a meaningful name
// (Indiranagar, Bengaluru) instead of the stub "Current location"
// string. Auth-gated because the upstream Google Geocoding API costs.
router.get('/reverse', requireAuth, ctrl.reverseGeocode);

module.exports = router;
