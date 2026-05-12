const Driver = require('../models/Driver');
const Unlock = require('../models/Unlock');
const ProcessedEvent = require('../models/ProcessedEvent');
const env = require('../config/env');
const razorpay = require('../services/razorpayClient');
const { HttpError } = require('../middleware/errorHandler');
const logger = require('../utils/logger');

// 30 days is well past Razorpay's retry window (a few hours) but short
// enough that the dedupe index stays cheap. TTL index on ProcessedEvent
// auto-prunes expired entries.
const WEBHOOK_DEDUPE_TTL_DAYS = 30;

// =============================================================================
// Razorpay webhook handler
//
// Razorpay POSTs at this endpoint after every payment lifecycle event with
// X-Razorpay-Signature = HMAC-SHA256(rawBody, webhookSecret). We MUST verify
// against the EXACT raw body — any reformatting (JSON parse + re-stringify
// loses key ordering and breaks the HMAC). The webhook router applies
// express.raw before this controller runs so req.body is a Buffer.
//
// Idempotency: Razorpay retries on any non-2xx response, and Cloud Run
// timeouts / transient network failures cause duplicates even when we
// processed the event successfully. We dedupe by `event.id` via the
// ProcessedEvent collection — a unique index throws E11000 on the second
// attempt and we short-circuit before re-applying the state change.
// =============================================================================
async function handleRazorpayWebhook(req, res, next) {
  try {
    const signature = req.header('x-razorpay-signature') || '';
    const rawBody = req.body; // Buffer when express.raw is mounted on this route
    if (!Buffer.isBuffer(rawBody)) {
      throw new HttpError(400, 'Webhook body must be raw bytes (express.raw missing?)');
    }

    const ok = razorpay.verifyWebhookSignature({
      rawBody: rawBody.toString('utf8'),
      signature,
    });
    if (!ok) throw new HttpError(401, 'Invalid webhook signature');

    const event = JSON.parse(rawBody.toString('utf8'));
    const eventId = event.id || event.payload?.payment?.entity?.id;
    logger.info(`Razorpay webhook event=${event.event} id=${eventId || 'unknown'}`);

    // Dedupe BEFORE state changes. If event.id is missing (shouldn't happen
    // with real Razorpay payloads, but webhook test fixtures sometimes omit
    // it), fall through without recording — better to risk a double-apply
    // than to silently swallow events we can't track.
    if (eventId) {
      const inserted = await tryRecordEvent({
        eventId,
        summary: `${event.event}:${event.payload?.payment?.entity?.id || ''}`,
      });
      if (!inserted) {
        logger.info(`Webhook event ${eventId} already processed — skipping`);
        return res.json({ received: true, deduped: true });
      }
    }

    // Razorpay's event names: payment.captured, payment.failed, order.paid, etc.
    // For v1 we care about payment.captured (covers both unlock + subscription).
    if (event.event === 'payment.captured') {
      await handlePaymentCaptured(event);
    }

    // Always 200 quickly — Razorpay retries on non-2xx, and a slow ack
    // turns into duplicate events. Heavy lifting goes in a queue when
    // we have one.
    res.json({ received: true });
  } catch (err) {
    next(err);
  }
}

/// Atomic "have I seen this event before?" check. Returns true if this
/// is the first time we're recording the id; false if it's a duplicate.
/// Any other failure (e.g. Mongo down) throws so the webhook 5xx's and
/// Razorpay retries — better to risk a duplicate than to drop an event.
async function tryRecordEvent({ eventId, summary }) {
  const expiresAt = new Date(
    Date.now() + WEBHOOK_DEDUPE_TTL_DAYS * 24 * 60 * 60 * 1000,
  );
  try {
    await ProcessedEvent.create({
      source: 'razorpay',
      eventId,
      summary,
      expiresAt,
    });
    return true;
  } catch (err) {
    // E11000 = unique-index violation = already processed.
    if (err && err.code === 11000) return false;
    throw err;
  }
}

async function handlePaymentCaptured(event) {
  const payment = event.payload?.payment?.entity;
  if (!payment) return;

  // We tagged orders with notes.kind so we know which path to credit.
  // Driver subscription notes: { kind: 'driver_subscription', driverId }
  const notes = payment.notes || {};
  const amountPaise = payment.amount;

  if (notes.kind === 'driver_subscription' && notes.driverId) {
    await activateDriverSubscription({
      driverId: notes.driverId,
      paymentId: payment.id,
      amountPaise,
    });
    return;
  }

  if (notes.kind === 'rider_unlock' && notes.riderId) {
    await mintRiderUnlock({
      riderId: notes.riderId,
      paymentId: payment.id,
      amountPaise,
    });
    return;
  }

  logger.warn(`payment.captured with unknown notes.kind=${notes.kind} id=${payment.id}`);
}

async function activateDriverSubscription({ driverId, paymentId, amountPaise }) {
  if (amountPaise < env.driverSub.pricePaise) {
    logger.warn(`Webhook underpayment for driver=${driverId} amount=${amountPaise}`);
    return;
  }
  const driver = await Driver.findById(driverId);
  if (!driver) {
    logger.warn(`Webhook for unknown driver=${driverId}`);
    return;
  }
  const now = new Date();
  const baseline = driver.subscriptionExpiresAt && driver.subscriptionExpiresAt > now
      ? driver.subscriptionExpiresAt
      : now;
  driver.subscriptionStartedAt = driver.subscriptionStartedAt ?? now;
  driver.subscriptionExpiresAt = new Date(
    baseline.getTime() + env.driverSub.daysPerCycle * 24 * 60 * 60 * 1000,
  );
  driver.subscriptionPaymentRef = paymentId;
  // Clear the reminder dedupe so next cycle's reminder fires.
  driver.subscriptionReminderSentAt = null;
  await driver.save();
  logger.info(`Webhook activated driver=${driverId} expiresAt=${driver.subscriptionExpiresAt.toISOString()}`);
}

async function mintRiderUnlock({ riderId, paymentId, amountPaise }) {
  if (amountPaise < env.unlock.pricePaise) {
    logger.warn(`Webhook underpayment for rider=${riderId} amount=${amountPaise}`);
    return;
  }
  const expiresAt = new Date(Date.now() + env.unlock.ttlSeconds * 1000);
  await Unlock.create({
    rider: riderId,
    source: 'payment',
    externalRef: paymentId,
    amountPaise,
    expiresAt,
  });
  logger.info(`Webhook minted unlock for rider=${riderId} via payment=${paymentId}`);
}

module.exports = { handleRazorpayWebhook };
