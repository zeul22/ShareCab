const express = require('express');
const router = express.Router();
const { handleRazorpayWebhook } = require('../controllers/paymentController');

// CRITICAL: Razorpay webhooks are HMAC'd against the EXACT raw body. The
// global express.json() in app.js parses JSON which would re-serialize and
// break the HMAC. Mount express.raw HERE, before the handler, so req.body
// is preserved as a Buffer. The handler converts to string for verification
// and parses with JSON.parse explicitly.
router.post(
  '/razorpay/webhook',
  express.raw({ type: 'application/json' }),
  handleRazorpayWebhook,
);

module.exports = router;
