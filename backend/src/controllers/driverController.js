const { z } = require('zod');
const Driver = require('../models/Driver');
const Trip = require('../models/Trip');
const env = require('../config/env');
const { HttpError } = require('../middleware/errorHandler');
const { isWithinIndia } = require('../utils/geo');
const razorpay = require('../services/razorpayClient');
const logger = require('../utils/logger');

const locationSchema = z
  .object({
    lat: z.number().min(-90).max(90),
    lng: z.number().min(-180).max(180),
  })
  .refine(isWithinIndia, { message: 'Coordinates must be within India' });

// Helper: load the requesting user's Driver record. Used everywhere in here.
async function loadDriverForRequest(req) {
  const driver = await Driver.findOne({ user: req.auth.userId });
  if (!driver) throw new HttpError(404, 'Driver profile not found');
  return driver;
}

async function setOnline(req, res, next) {
  try {
    const driver = await loadDriverForRequest(req);

    // Subscription gate. Drivers without an active subscription cannot
    // accept dispatches — this is the entire monetisation surface for
    // the driver side. Free trial is granted at signup so first-month
    // drivers always pass; renewal happens via /subscribe.
    if (!driver.isSubscribed) {
      throw new HttpError(
        403,
        'Subscription expired. Renew at /api/drivers/subscribe to go online.',
      );
    }

    driver.isOnline = true;
    await driver.save();
    res.json({ driver });
  } catch (err) {
    next(err);
  }
}

async function setOffline(req, res, next) {
  try {
    const driver = await Driver.findOneAndUpdate(
      { user: req.auth.userId },
      { $set: { isOnline: false } },
      { new: true },
    );
    if (!driver) throw new HttpError(404, 'Driver profile not found');
    res.json({ driver });
  } catch (err) {
    next(err);
  }
}

async function updateLocation(req, res, next) {
  try {
    const { lat, lng } = locationSchema.parse(req.body);
    const driver = await Driver.findOneAndUpdate(
      { user: req.auth.userId },
      { $set: { currentLocation: { type: 'Point', coordinates: [lng, lat] } } },
      { new: true },
    );
    if (!driver) throw new HttpError(404, 'Driver profile not found');
    res.json({ driver });
  } catch (err) {
    next(err);
  }
}

// =============================================================================
// Subscription endpoints
//
// Two-step Razorpay flow (stubbed for now, real integration later):
//   1. POST /subscribe — driver hits this when they want to renew.
//      In prod: create a Razorpay Order, return order_id + key for the
//      driver app to invoke checkout.
//      In stub: returns a fake order_id so the demo flow can call confirm.
//   2. POST /subscribe/confirm — Razorpay webhook calls this on payment
//      success. We verify the HMAC (TODO) and extend subscriptionExpiresAt
//      by env.driverSub.daysPerCycle.
//
// Renewal logic: extend from CURRENT expiry (if still active) so renewing
// early doesn't cost the driver paid-up days. Otherwise extend from now.
// =============================================================================

// Full driver record for the driver-home screen. Returns the public-safe
// subset of the Driver doc plus a derived `isSubscribed` flag so the
// client doesn't have to compute it from the timestamp.
async function getMyDriver(req, res, next) {
  try {
    const driver = await loadDriverForRequest(req);
    res.json({
      driver: {
        _id: driver._id,
        user: driver.user,
        licenseNumber: driver.licenseNumber,
        vehicle: driver.vehicle,
        isOnline: driver.isOnline,
        activeTrips: driver.activeTrips,
        currentLocation: driver.currentLocation,
        subscription: {
          isSubscribed: driver.isSubscribed,
          startedAt: driver.subscriptionStartedAt,
          expiresAt: driver.subscriptionExpiresAt,
          paymentRef: driver.subscriptionPaymentRef,
        },
      },
    });
  } catch (err) {
    next(err);
  }
}

// Currently dispatched trips for the requesting driver. Returns the same
// populated shape as `GET /api/trips/:id` but for every trip in the driver's
// activeTrips list — so a shared (group) dispatch returns 2-3 trips that
// the client can stitch into a route. Returns an empty list (not 404) when
// the driver has no dispatch; the client polls this on a tick and a
// no-dispatch state is a normal answer, not an error.
async function getMyDispatch(req, res, next) {
  try {
    const driver = await loadDriverForRequest(req);
    if (!driver.activeTrips || driver.activeTrips.length === 0) {
      return res.json({ trips: [] });
    }
    const trips = await Trip.find({ _id: { $in: driver.activeTrips } })
      .populate([
        { path: 'rider', select: 'name rating phone' },
        {
          path: 'matchGroup',
          populate: {
            path: 'trips',
            select: 'rider pickup dropoff status',
            populate: { path: 'rider', select: 'name rating' },
          },
        },
      ]);
    res.json({ trips });
  } catch (err) {
    next(err);
  }
}

async function getMySubscription(req, res, next) {
  try {
    const driver = await loadDriverForRequest(req);
    res.json({
      isSubscribed: driver.isSubscribed,
      startedAt: driver.subscriptionStartedAt,
      expiresAt: driver.subscriptionExpiresAt,
      paymentRef: driver.subscriptionPaymentRef,
      pricePaise: env.driverSub.pricePaise,
      daysPerCycle: env.driverSub.daysPerCycle,
    });
  } catch (err) {
    next(err);
  }
}

async function startSubscriptionOrder(req, res, next) {
  try {
    const driver = await loadDriverForRequest(req);
    const order = await razorpay.createOrder({
      amountPaise: env.driverSub.pricePaise,
      receipt: `drvsub_${driver._id}_${Date.now()}`,
      notes: { kind: 'driver_subscription', driverId: String(driver._id) },
    });
    logger.info(
      `Subscription order created driver=${driver._id} order=${order.id} ` +
      `pricePaise=${env.driverSub.pricePaise} stub=${Boolean(order.stub)}`,
    );
    res.json({
      orderId: order.id,
      amountPaise: env.driverSub.pricePaise,
      currency: 'INR',
      // The client SDK needs this to invoke checkout. Empty string in stub
      // mode signals to the app that it's running without real keys.
      razorpayKeyId: env.razorpay.keyId,
    });
  } catch (err) {
    next(err);
  }
}

// Razorpay's checkout.js callback posts these three fields. paymentRef is
// kept as an alias so the demo flow (without real checkout) can fill in
// just paymentRef and a stub signature; production MUST send all three
// real fields plus the signature for HMAC verification to pass.
const confirmSchema = z.object({
  orderId: z.string().min(1),
  paymentRef: z.string().min(1), // razorpay_payment_id
  amountPaise: z.number().int().positive(),
  signature: z.string().optional(), // razorpay_signature; required in prod
});

async function confirmSubscription(req, res, next) {
  try {
    const data = confirmSchema.parse(req.body);
    const driver = await loadDriverForRequest(req);

    // Verify the signature posted by Razorpay checkout. In stub mode
    // (no API keys configured) this passes through with a logged warning;
    // configured prod will reject anything without a valid HMAC.
    const ok = razorpay.verifyPaymentSignature({
      orderId: data.orderId,
      paymentId: data.paymentRef,
      signature: data.signature || '',
    });
    if (!ok) throw new HttpError(401, 'Invalid Razorpay signature');

    if (data.amountPaise < env.driverSub.pricePaise) {
      throw new HttpError(
        400,
        `Underpayment: received ${data.amountPaise} paise, expected ${env.driverSub.pricePaise}`,
      );
    }

    const now = new Date();
    // Extend from whichever is later: current expiry or now. Lets drivers
    // renew early without forfeiting unused days.
    const baseline = driver.subscriptionExpiresAt && driver.subscriptionExpiresAt > now
        ? driver.subscriptionExpiresAt
        : now;
    const newExpiry = new Date(
      baseline.getTime() + env.driverSub.daysPerCycle * 24 * 60 * 60 * 1000,
    );

    driver.subscriptionStartedAt = driver.subscriptionStartedAt ?? now;
    driver.subscriptionExpiresAt = newExpiry;
    driver.subscriptionPaymentRef = data.paymentRef;
    // Renewal succeeded — clear the reminder dedupe so the next cycle's
    // "expiring soon" reminder fires when its time comes.
    driver.subscriptionReminderSentAt = null;
    await driver.save();

    logger.info(
      `Subscription activated driver=${driver._id} expiresAt=${newExpiry.toISOString()} ` +
      `paymentRef=${data.paymentRef}`,
    );
    res.json({
      isSubscribed: driver.isSubscribed,
      startedAt: driver.subscriptionStartedAt,
      expiresAt: driver.subscriptionExpiresAt,
    });
  } catch (err) {
    next(err);
  }
}

module.exports = {
  setOnline,
  setOffline,
  updateLocation,
  getMyDriver,
  getMyDispatch,
  getMySubscription,
  startSubscriptionOrder,
  confirmSubscription,
};
