const router = require('express').Router();
const {
  signup,
  login,
  me,
  requestOtp,
  verifyOtp,
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
router.post('/refresh', refreshSession);
router.post('/logout', logout);

module.exports = router;
