const crypto = require('crypto');
const env = require('../config/env');
const logger = require('../utils/logger');

// Lazy-loaded Razorpay SDK so the dev server doesn't crash on startup if
// the package is somehow missing or env keys aren't configured.
let _client = null;
function getClient() {
  if (_client) return _client;
  if (!env.razorpay.keyId || !env.razorpay.keySecret) return null;
  // require() inside the function so we never even pull the SDK in stub mode.
  const Razorpay = require('razorpay');
  _client = new Razorpay({
    key_id: env.razorpay.keyId,
    key_secret: env.razorpay.keySecret,
  });
  return _client;
}

function isConfigured() {
  return Boolean(env.razorpay.keyId && env.razorpay.keySecret);
}

// ---------------------------------------------------------------------------
// Order creation
//
// Caller passes amount in paise + a receipt id; we hand back whatever
// Razorpay gives us (real order_id, status, etc) — or a stub equivalent
// when keys are unconfigured. The stub keeps the same response shape so
// downstream code doesn't need to branch.
// ---------------------------------------------------------------------------
async function createOrder({ amountPaise, receipt, notes }) {
  const client = getClient();
  if (!client) {
    const stubId = `stub_order_${crypto.randomBytes(8).toString('hex')}`;
    logger.warn(
      `Razorpay stub mode (RAZORPAY_KEY_ID/SECRET unset). ` +
      `Returning fake order ${stubId} for receipt=${receipt} amount=${amountPaise}`,
    );
    return {
      id: stubId,
      amount: amountPaise,
      currency: 'INR',
      status: 'created',
      receipt,
      stub: true,
    };
  }
  return client.orders.create({
    amount: amountPaise,
    currency: 'INR',
    receipt,
    notes,
  });
}

// ---------------------------------------------------------------------------
// Signature verification (client-side checkout success callback)
//
// Razorpay's checkout.js posts back razorpay_order_id, razorpay_payment_id,
// razorpay_signature. The signature is HMAC-SHA256("$orderId|$paymentId",
// keySecret). Verifying it server-side is the only way to trust the success
// callback — without this, anyone with curl can forge a successful payment.
// ---------------------------------------------------------------------------
function verifyPaymentSignature({ orderId, paymentId, signature }) {
  if (!isConfigured()) {
    // Dev-mode pass-through: log loudly but don't reject. Production must
    // fail closed by setting keys; CI / staging should as well.
    logger.warn('Razorpay signature check SKIPPED (stub mode).');
    return true;
  }
  const expected = crypto
    .createHmac('sha256', env.razorpay.keySecret)
    .update(`${orderId}|${paymentId}`)
    .digest('hex');
  return timingSafeEqualHex(expected, signature);
}

// ---------------------------------------------------------------------------
// Webhook signature verification (server-to-server)
//
// Razorpay POSTs webhook events with X-Razorpay-Signature = HMAC-SHA256
// of the RAW request body using the *webhook secret* (different from the
// API key secret). The express raw body must be preserved — see the
// webhook router which mounts express.raw before this verifier runs.
// ---------------------------------------------------------------------------
function verifyWebhookSignature({ rawBody, signature }) {
  if (!env.razorpay.webhookSecret) {
    logger.warn('Razorpay webhook signature check SKIPPED (RAZORPAY_WEBHOOK_SECRET unset).');
    return true;
  }
  const expected = crypto
    .createHmac('sha256', env.razorpay.webhookSecret)
    .update(rawBody)
    .digest('hex');
  return timingSafeEqualHex(expected, signature);
}

function timingSafeEqualHex(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  if (a.length !== b.length) return false;
  try {
    return crypto.timingSafeEqual(Buffer.from(a, 'hex'), Buffer.from(b, 'hex'));
  } catch {
    return false;
  }
}

module.exports = {
  isConfigured,
  createOrder,
  verifyPaymentSignature,
  verifyWebhookSignature,
};
