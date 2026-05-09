const router = require('express').Router();
const { requireAuth } = require('../middleware/auth');
const ctrl = require('../controllers/unlockController');

// Server-to-server callbacks. No requireAuth — the AdMob HMAC signature and
// the Razorpay HMAC signature serve as authentication once the verification
// TODOs in unlockController are implemented.
router.post('/ad-reward', ctrl.createAdRewardUnlock);
router.post('/payment-confirm', ctrl.createPaymentUnlock);

router.get('/me', requireAuth, ctrl.getMyUnlocks);

module.exports = router;
