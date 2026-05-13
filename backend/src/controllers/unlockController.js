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
    //
    // safeParse + 400 — the prior `.parse` threw a raw ZodError with no
    // .status, which the global error handler surfaced as 500.
    const parsed = adRewardSchema.safeParse(req.body);
    if (!parsed.success) {
      throw new HttpError(400, 'Invalid ad-reward payload: needs { adsCompleted: positive int }');
    }
    const data = parsed.data;
    // Rider id comes from the JWT, not the body — see the route comment.
    const riderId = req.auth.userId;

    // Look up the rider's rating to determine how many ads they actually
    // need. A new account defaults to 5.0★ in the User schema so first-time
    // riders get the top tier; ratings below 4.0 face stricter friction.
    const rider = await User.findById(riderId, { rating: 1 });
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
      rider: riderId,
      source: 'ad',
      externalRef: data.externalRef,
      expiresAt,
    });
    logger.info(
      `Unlock ${unlock._id} minted for rider ${riderId} (rating=${rider.rating}, ` +
      `requiredAds=${required}) via ad`,
    );
    res.status(201).json({ unlock, requiredAds: required });
  } catch (err) {
    next(err);
  }
}

const paymentSchema = z.object({
  // razorpay_order_id from the order we created earlier (paymentSchema's
  // `externalRef` previously aliased this to the payment_id; we keep both
  // explicit for signature verification).
  orderId: z.string().optional(),
  externalRef: z.string().min(1), // razorpay_payment_id
  amountPaise: z.number().int().positive(),
  signature: z.string().optional(), // razorpay_signature; required in prod
});

async function createPaymentUnlock(req, res, next) {
  try {
    // safeParse + 400 — prior `.parse` threw a raw ZodError with no
    // .status, which the global error handler surfaced as 500. Bad
    // payloads now return a readable 400.
    const parsed = paymentSchema.safeParse(req.body);
    if (!parsed.success) {
      throw new HttpError(
        400,
        'Invalid payment-confirm payload: needs { externalRef, amountPaise }',
      );
    }
    const data = parsed.data;
    // Rider id from the JWT, not the body — closes the privilege-
    // escalation hole where any caller with a Razorpay paymentId could
    // mint an unlock against any rider account.
    const riderId = req.auth.userId;

    // Verify the checkout signature when a REAL orderId was supplied.
    // Three branches:
    //   1. Real Razorpay order id → verify HMAC. razorpayClient
    //      short-circuits to true when no keys are configured at all
    //      (full stub mode / local dev with no creds), so this still
    //      works for the original demo flow.
    //   2. Stub-prefixed order id (`stub_` / `stub_fallback_`) → the
    //      backend itself minted this when Razorpay rejected our
    //      createOrder. Only honour it when bypass is enabled, since
    //      that's the same gate as the no-orderId case below.
    //   3. No orderId at all → client took the bypass path after the
    //      Razorpay sheet errored. Gated on the env flag too.
    const isStubOrder =
      data.orderId && data.orderId.startsWith('stub_');
    if (data.orderId && !isStubOrder) {
      const ok = razorpay.verifyPaymentSignature({
        orderId: data.orderId,
        paymentId: data.externalRef,
        signature: data.signature || '',
      });
      if (!ok) throw new HttpError(401, 'Invalid Razorpay signature');
    } else if (!env.unlock.paymentBypassEnabled) {
      throw new HttpError(
        402,
        'Payment bypass disabled on this server — real Razorpay orderId required.',
      );
    } else {
      logger.warn(
        `[unlock] payment-bypass MINTED for rider=${riderId} externalRef=${data.externalRef} ` +
        `orderId=${data.orderId || '(none)'} — set UNLOCK_PAYMENT_BYPASS=false to enforce real payments`,
      );
    }

    if (data.amountPaise < env.unlock.pricePaise) {
      throw new HttpError(
        400,
        `Underpayment: received ${data.amountPaise} paise, expected ${env.unlock.pricePaise}`,
      );
    }

    const expiresAt = new Date(Date.now() + env.unlock.ttlSeconds * 1000);
    const unlock = await Unlock.create({
      rider: riderId,
      source: 'payment',
      externalRef: data.externalRef,
      amountPaise: data.amountPaise,
      expiresAt,
    });
    logger.info(
      `Unlock ${unlock._id} minted for rider ${riderId} via payment ${data.externalRef}`,
    );
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
    try {
      const order = await razorpay.createOrder({
        amountPaise: env.unlock.pricePaise,
        receipt: `unlock_${riderId}_${Date.now()}`,
        notes: { kind: 'rider_unlock', riderId: String(riderId) },
      });
      logger.info(
        `Unlock order created rider=${riderId} order=${order.id} ` +
        `pricePaise=${env.unlock.pricePaise} stub=${Boolean(order.stub)}`,
      );
      return res.json({
        orderId: order.id,
        amountPaise: env.unlock.pricePaise,
        currency: 'INR',
        // Empty in stub mode — the client uses this as a signal to
        // skip the Razorpay sheet entirely and confirm with a
        // synthetic paymentRef. We also force this to empty when we
        // fell back to stub below, so the client knows not to try
        // opening the real Razorpay sheet against a fake order id.
        razorpayKeyId: order.stub ? '' : env.razorpay.keyId,
      });
    } catch (err) {
      // Razorpay SDK rejected (bad/revoked keys, network blip, rate
      // limit, etc.). Previously this 500'd because the SDK error
      // has no `.status` field and fell through the global handler.
      //
      // Behaviour now depends on env.unlock.paymentBypassEnabled:
      //   - bypass enabled (default in dev) → mint a synthetic stub
      //     order so the client can complete the unlock through the
      //     stub flow without a working Razorpay account. Logged
      //     loud + clear so it's not silently masked in production.
      //   - bypass disabled (production) → translate to HttpError(502)
      //     with the upstream reason so the rider sees a clear
      //     "payments unavailable, try again" instead of "Internal
      //     Server Error."
      if (env.unlock.paymentBypassEnabled) {
        const stubId = `stub_fallback_${Date.now()}_${riderId}`;
        logger.warn(
          `[unlock-order] Razorpay rejected (${err.message || err}) — ` +
          `falling back to stub order ${stubId}. ` +
          `Set UNLOCK_PAYMENT_BYPASS=false to enforce real payments.`,
        );
        return res.json({
          orderId: stubId,
          amountPaise: env.unlock.pricePaise,
          currency: 'INR',
          razorpayKeyId: '', // forces stub path on the client
        });
      }
      throw new HttpError(
        502,
        `Payment provider unavailable (${err.message || 'unknown'}). ` +
          'Please try again or watch ads to unlock.',
      );
    }
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
