const router = require('express').Router();
const { requireAuth } = require('../middleware/auth');
const ctrl = require('../controllers/unlockController');

// Server-to-server callbacks. No requireAuth — the AdMob HMAC signature and
// the Razorpay HMAC signature serve as authentication once the verification
// TODOs in unlockController are implemented.
router.post('/ad-reward', ctrl.createAdRewardUnlock);
router.post('/payment-confirm', ctrl.createPaymentUnlock);

// Razorpay order creation for the unlock pay path. requireAuth because the
// rider id MUST come from the JWT — letting the client pass it in the body
// would let anyone mint an unlock receipt against any rider account.
router.post('/order', requireAuth, ctrl.startUnlockOrder);

router.get('/me', requireAuth, ctrl.getMyUnlocks);

module.exports = router;
