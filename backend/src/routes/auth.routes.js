const router = require('express').Router();
const {
  signup,
  login,
  me,
  requestOtp,
  verifyOtp,
  verifyMsg91Otp,
  refreshSession,
  logout,
} = require('../controllers/authController');
const { requireAuth } = require('../middleware/auth');

// Phone+password (used by demo seed scripts and admin tooling).
router.post('/signup', signup);
router.post('/login', login);
router.get('/me', requireAuth, me);

// Phone+OTP (used by the Flutter app). Account auto-creates on first verify.
router.post('/otp/request', requestOtp);
router.post('/otp/verify', verifyOtp);
// MSG91 OTP exchange. The Flutter app's MSG91 widget mints an access
// token after the user enters the OTP; we verify it against MSG91's
// verifyAccessToken and issue our own session.
router.post('/otp/msg91/verify', verifyMsg91Otp);
router.post('/refresh', refreshSession);
router.post('/logout', logout);

module.exports = router;
