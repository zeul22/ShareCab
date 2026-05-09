const { z } = require('zod');
const Unlock = require('../models/Unlock');
const env = require('../config/env');
const { HttpError } = require('../middleware/errorHandler');
const logger = require('../utils/logger');

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
    //   - Only mint an Unlock once env.unlock.adsPerUnlock reached
    const data = adRewardSchema.parse(req.body);

    if (data.adsCompleted < env.unlock.adsPerUnlock) {
      throw new HttpError(
        400,
        `Need ${env.unlock.adsPerUnlock} rewarded ads to unlock matching, got ${data.adsCompleted}`,
      );
    }

    const expiresAt = new Date(Date.now() + env.unlock.ttlSeconds * 1000);
    const unlock = await Unlock.create({
      rider: data.riderId,
      source: 'ad',
      externalRef: data.externalRef,
      expiresAt,
    });
    logger.info(`Unlock ${unlock._id} minted for rider ${data.riderId} via ad`);
    res.status(201).json({ unlock });
  } catch (err) {
    next(err);
  }
}

const paymentSchema = z.object({
  riderId: z.string(),
  externalRef: z.string(), // razorpay payment_id
  amountPaise: z.number().int().positive(),
});

async function createPaymentUnlock(req, res, next) {
  try {
    // TODO(razorpay-webhook): replace stub with real Razorpay webhook handler.
    //   - Verify X-Razorpay-Signature HMAC against the raw request body
    //   - Look up internal order by razorpay_order_id; reject if already credited
    //   - Confirm amountPaise == env.unlock.pricePaise (no over/underpay surprise)
    const data = paymentSchema.parse(req.body);

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

module.exports = { createAdRewardUnlock, createPaymentUnlock, getMyUnlocks };
