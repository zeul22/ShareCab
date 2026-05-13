const router = require('express').Router();
const { requireAuth } = require('../middleware/auth');
const ctrl = require('../controllers/unlockController');

// Client-driven mint endpoints. Both require auth so the rider id comes
// from the JWT, NOT the request body — otherwise anyone with a paymentId
// could forge an unlock against any rider account. The Razorpay signature
// + (future) AdMob SSV signature are layered on top of auth, not instead
// of it. When a real AdMob server-to-server SSV route is added later,
// give it its own path (e.g. POST /unlocks/admob/ssv) with HMAC-only auth.
router.post('/ad-reward', requireAuth, ctrl.createAdRewardUnlock);
router.post('/payment-confirm', requireAuth, ctrl.createPaymentUnlock);

// Razorpay order creation for the unlock pay path. requireAuth because the
// rider id MUST come from the JWT — letting the client pass it in the body
// would let anyone mint an unlock receipt against any rider account.
router.post('/order', requireAuth, ctrl.startUnlockOrder);

router.get('/me', requireAuth, ctrl.getMyUnlocks);

module.exports = router;
