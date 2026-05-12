const { z } = require('zod');
const Unlock = require('../models/Unlock');
const User = require('../models/User');
const env = require('../config/env');
const razorpay = require('../services/razorpayClient');
const { HttpError } = require('../middleware/errorHandler');
const logger = require('../utils/logger');

// Rating tiers that drive how many rewarded ads a rider must complete to
// earn an unlock. Punishes flaky / low-rated users with more friction
// without locking them out, rewards reliable users with a fast path.
//
// Tiers (highest match wins):
//   ≥ 4.5★ → 1 ad (fast path for top riders)
//   ≥ 4.0★ → adsPerUnlock from env (current default, 2)
//   < 4.0★ → adsPerUnlock + 1 (extra friction)
function adsRequiredForRating(rating) {
  const r = Number.isFinite(rating) ? rating : 5;
  const base = env.unlock.adsPerUnlock;
  if (r >= 4.5) return Math.max(1, base - 1);
  if (r >= 4.0) return base;
  return base + 1;
}

const adRewardSchema = z.object({
  riderId: z.string(),
  // AdMob fires one SSV callback per rewarded ad. The real handler will track
  // counts per rider and mint an unlock when the threshold is hit; the stub
  // accepts the count directly to keep the flow easy to exercise.
  adsCompleted: z.number().int().min(1),
  externalRef: z.string().optional(),
});

async function createAdRewardUnlock(req, res, next) {
  try {
    // TODO(admob-ssv): replace stub with real AdMob Server-Side Verification.
    //   - Verify HMAC signature using AdMob's public key for the given key_id
    //   - Track per-rider rewarded-ad count via a separate collection, dedup on transaction_id
    //   - Only mint an Unlock once the per-rating threshold is reached
    const data = adRewardSchema.parse(req.body);

    // Look up the rider's rating to determine how many ads they actually
    // need. A new account defaults to 5.0★ in the User schema so first-time
    // riders get the top tier; ratings below 4.0 face stricter friction.
    const rider = await User.findById(data.riderId, { rating: 1 });
    if (!rider) throw new HttpError(404, 'Rider not found');
    const required = adsRequiredForRating(rider.rating);

    if (data.adsCompleted < required) {
      throw new HttpError(
        400,
        `Need ${required} rewarded ads to unlock matching, got ${data.adsCompleted}`,
      );
    }

    const expiresAt = new Date(Date.now() + env.unlock.ttlSeconds * 1000);
    const unlock = await Unlock.create({
      rider: data.riderId,
      source: 'ad',
      externalRef: data.externalRef,
      expiresAt,
    });
    logger.info(
      `Unlock ${unlock._id} minted for rider ${data.riderId} (rating=${rider.rating}, ` +
      `requiredAds=${required}) via ad`,
    );
    res.status(201).json({ unlock, requiredAds: required });
  } catch (err) {
    next(err);
  }
}

const paymentSchema = z.object({
  riderId: z.string(),
  // razorpay_order_id from the order we created earlier (paymentSchema's
  // `externalRef` previously aliased this to the payment_id; we keep both
  // explicit for signature verification).
  orderId: z.string().optional(),
  externalRef: z.string(), // razorpay_payment_id
  amountPaise: z.number().int().positive(),
  signature: z.string().optional(), // razorpay_signature; required in prod
});

async function createPaymentUnlock(req, res, next) {
  try {
    const data = paymentSchema.parse(req.body);

    // Verify the checkout signature when provided + keys configured. Stub
    // mode (no keys) passes through with a warning so the demo still works.
    if (data.orderId) {
      const ok = razorpay.verifyPaymentSignature({
        orderId: data.orderId,
        paymentId: data.externalRef,
        signature: data.signature || '',
      });
      if (!ok) throw new HttpError(401, 'Invalid Razorpay signature');
    }

    if (data.amountPaise < env.unlock.pricePaise) {
      throw new HttpError(
        400,
        `Underpayment: received ${data.amountPaise} paise, expected ${env.unlock.pricePaise}`,
      );
    }

    const expiresAt = new Date(Date.now() + env.unlock.ttlSeconds * 1000);
    const unlock = await Unlock.create({
      rider: data.riderId,
      source: 'payment',
      externalRef: data.externalRef,
      amountPaise: data.amountPaise,
      expiresAt,
    });
    logger.info(`Unlock ${unlock._id} minted for rider ${data.riderId} via payment ${data.externalRef}`);
    res.status(201).json({ unlock });
  } catch (err) {
    next(err);
  }
}

async function getMyUnlocks(req, res, next) {
  try {
    const now = new Date();
    const unlocks = await Unlock.find({
      rider: req.auth.userId,
      usedAt: null,
      expiresAt: { $gt: now },
    }).sort({ expiresAt: 1 });
    res.json({ unlocks });
  } catch (err) {
    next(err);
  }
}

// =============================================================================
// Razorpay order creation for the rider unlock pay path.
//
// Two-step flow, mirrors driver subscription:
//   1. Client POST /unlocks/order. We create a Razorpay order tagged with
//      notes.kind=rider_unlock + riderId, return orderId + amount + keyId
//      for the Flutter checkout sheet.
//   2. After Razorpay's success callback, client POST /unlocks/payment-confirm
//      with orderId + paymentRef + signature. We verify the HMAC, mint the
//      Unlock.
//
// The webhook handler in paymentController is the safety net — if the
// client-side confirm call never lands (network drop after payment), the
// payment.captured webhook still mints the unlock via notes.kind dispatch.
// =============================================================================
async function startUnlockOrder(req, res, next) {
  try {
    const riderId = req.auth.userId;
    const order = await razorpay.createOrder({
      amountPaise: env.unlock.pricePaise,
      receipt: `unlock_${riderId}_${Date.now()}`,
      notes: { kind: 'rider_unlock', riderId: String(riderId) },
    });
    logger.info(
      `Unlock order created rider=${riderId} order=${order.id} ` +
      `pricePaise=${env.unlock.pricePaise} stub=${Boolean(order.stub)}`,
    );
    res.json({
      orderId: order.id,
      amountPaise: env.unlock.pricePaise,
      currency: 'INR',
      // Empty in stub mode — the client uses this as a signal to skip the
      // Razorpay sheet entirely and confirm with a synthetic paymentRef.
      razorpayKeyId: env.razorpay.keyId,
    });
  } catch (err) {
    next(err);
  }
}

module.exports = {
  createAdRewardUnlock,
  createPaymentUnlock,
  getMyUnlocks,
  startUnlockOrder,
};
