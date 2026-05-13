const router = require('express').Router();
const { requireAuth } = require('../middleware/auth');
const ctrl = require('../controllers/ratingController');

// POST /api/ratings — rate a co-rider (or the driver). Idempotent
// per (trip, rater, ratee): repeat calls 409.
router.post('/', requireAuth, ctrl.rate);

// POST /api/ratings/skip — explicitly decline to rate a co-rider.
// Applies -0.25 to the SKIPPER's own rating.
router.post('/skip', requireAuth, ctrl.skipRating);

// GET /api/ratings/pending — co-riders this user still owes a
// decision (rate-or-skip) on. Drives the rider app's auto-prompt.
router.get('/pending', requireAuth, ctrl.getMyPendingCoRiderRatings);

module.exports = router;
