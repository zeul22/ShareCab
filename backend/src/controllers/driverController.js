const { z } = require('zod');
const Driver = require('../models/Driver');
const Trip = require('../models/Trip');
const User = require('../models/User');
const env = require('../config/env');
const { HttpError } = require('../middleware/errorHandler');
const { isWithinIndia } = require('../utils/geo');
const razorpay = require('../services/razorpayClient');
const dispatchService = require('../services/dispatchService');
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

    if (!env.dispatch.driverOpsEnabled) {
      throw new HttpError(
        403,
        'Driver operations are disabled in public demo mode.',
      );
    }

    // Verification gate. Drivers must clear ops review before they can
    // accept dispatches — this is the first thing the driver app checks
    // and the same gate is enforced server-side so a malicious client
    // can't bypass it. 'rejected' surfaces the same 403 as 'pending'.
    if (driver.verificationStatus !== 'approved') {
      throw new HttpError(
        403,
        'Account is still under review. You will be able to go online once approved.',
      );
    }

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
    // safeParse — driver location is pushed every ~20s while online,
    // so a single bad fix (sim in Cupertino, GPS glitch in a tunnel)
    // shouldn't 500 the entire push. We DO still reject obviously-bad
    // structural input (missing lat/lng) as 400 because the contract
    // is the body shape; out-of-bounds is treated as "ignore this
    // fix, wait for the next one." That mirrors how the trip-time
    // actualPickup capture handles bad coords.
    const result = locationSchema.safeParse(req.body);
    if (!result.success) {
      // Missing / non-numeric lat-lng is a client bug → 400.
      const fields = (result.error.issues || []).map((i) => i.path.join('.'));
      const isStructural = fields.some(
        (f) => f === 'lat' || f === 'lng' || f === '',
      );
      if (isStructural) {
        throw new HttpError(
          400,
          'Invalid location payload — needs { lat, lng } as numbers.',
        );
      }
      // Out-of-India refine failure → 204 (accepted, nothing stored).
      // Returning 204 instead of 200 so the driver app can tell its own
      // location-push loop apart from a saved fix.
      logger.warn(
        `[updateLocation] dropping out-of-bounds fix lat=${req.body?.lat} lng=${req.body?.lng}`,
      );
      return res.status(204).end();
    }
    const { lat, lng } = result.data;
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
        verificationStatus: driver.verificationStatus,
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

// =============================================================================
// Driver onboarding
//
// Mirrors the Rapido/Uber/Ola first-launch flow: a logged-in rider submits
// the wizard payload here, the backend creates a Driver document with
// verificationStatus='pending' and promotes their User.role to 'driver'.
//
// Ops manually flips verificationStatus → 'approved' in the dashboard
// (admin UI is out of scope here; for now an internal Mongo update or a
// future /admin endpoint handles it). When MSG91_DEV_FALLBACK is on we
// auto-approve so the dev demo doesn't get stuck on the pending screen.
// =============================================================================

const onboardSchema = z.object({
  fullName: z.string().min(2).max(80),
  email: z.string().email().optional(),
  licenseNumber: z.string().min(4).max(32),
  vehicle: z.object({
    model: z.string().min(2).max(60),
    plate: z.string().min(4).max(16),
    color: z.string().max(30).optional(),
    capacity: z.number().int().min(1).max(8).optional(),
  }),
});

async function onboardDriver(req, res, next) {
  try {
    const data = onboardSchema.parse(req.body);

    const existing = await Driver.findOne({ user: req.auth.userId });
    if (existing) {
      throw new HttpError(409, 'Driver profile already exists');
    }

    const user = await User.findById(req.auth.userId);
    if (!user) throw new HttpError(404, 'User not found');

    // Grant the trial subscription so the driver isn't double-blocked
    // (verification AND subscription) the moment ops approves them.
    const trialDays = env.driverSub.freeTrialDays;
    const now = new Date();
    const trialExpiresAt = trialDays > 0
      ? new Date(now.getTime() + trialDays * 24 * 60 * 60 * 1000)
      : null;

    // Dev fallback auto-approves so local demos don't stall on the
    // pending screen. Production drivers wait for the ops dashboard.
    const verificationStatus = env.msg91.devFallback ? 'approved' : 'pending';

    const driver = await Driver.create({
      user: user._id,
      licenseNumber: data.licenseNumber.toUpperCase(),
      vehicle: {
        model: data.vehicle.model,
        plate: data.vehicle.plate.toUpperCase(),
        color: data.vehicle.color,
        capacity: data.vehicle.capacity ?? 4,
      },
      verificationStatus,
      subscriptionStartedAt: trialDays > 0 ? now : null,
      subscriptionExpiresAt: trialExpiresAt,
      subscriptionPaymentRef: trialDays > 0 ? 'free-trial' : null,
    });

    // Promote the User role + capture the driver-app name/email. Both
    // are saved on the User doc so the rider app (if the same person
    // had a rider session) sees the new role on their next refresh.
    user.role = 'driver';
    user.name = data.fullName;
    if (data.email) user.email = data.email;
    await user.save();

    logger.info(
      `Driver onboarded user=${user._id} status=${verificationStatus} ` +
      `plate=${driver.vehicle.plate}`,
    );

    res.status(201).json({
      driver: {
        _id: driver._id,
        user: driver.user,
        licenseNumber: driver.licenseNumber,
        vehicle: driver.vehicle,
        isOnline: driver.isOnline,
        activeTrips: driver.activeTrips,
        currentLocation: driver.currentLocation,
        verificationStatus: driver.verificationStatus,
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

// =============================================================================
// Driver offer endpoints — the Uber-style accept/reject layer.
//
// Replaces the V1 auto-assignment flow. Now the matching engine OFFERS a
// trip to the nearest driver (status='offered'); the driver app polls
// `GET /drivers/me/offer` at 3s cadence, surfaces a sheet with countdown,
// and POSTs to /offers/:id/accept | /reject. Backend timeout fires
// auto-reject after env.dispatch.offerTimeoutMs so a missing driver
// doesn't strand a rider. See services/dispatchService.js.
// =============================================================================

// One-shot snapshot for the driver-home screen's poll. Returns 204 when
// no offer is pending (cheap signal for the client to keep waiting).
async function getMyOffer(req, res, next) {
  try {
    const driver = await Driver.findOne({ user: req.auth.userId }, { _id: 1 });
    if (!driver) throw new HttpError(404, 'Driver profile not found');

    // Match by offeredTo + status='offered' AND not yet expired. Pulling
    // ONE trip is enough — for a group offer all siblings carry the same
    // offeredTo, and the sheet surfaces the group via the trip's
    // populated matchGroup.
    const trip = await Trip.findOne({
      offeredTo: driver._id,
      status: 'offered',
      offerExpiresAt: { $gt: new Date() },
    }).populate([
      { path: 'rider', select: 'name rating phone' },
      {
        path: 'matchGroup',
        populate: {
          path: 'trips',
          select: 'rider pickup dropoff fareEstimate fareBreakdown',
          populate: { path: 'rider', select: 'name rating' },
        },
      },
    ]);

    if (!trip) {
      res.set('Cache-Control', 'no-store');
      return res.status(204).end();
    }

    res.set('Cache-Control', 'no-store');
    res.json({ offer: trip });
  } catch (err) {
    next(err);
  }
}

async function acceptOffer(req, res, next) {
  try {
    const driver = await Driver.findOne({ user: req.auth.userId }, { _id: 1 });
    if (!driver) throw new HttpError(404, 'Driver profile not found');

    const result = await dispatchService.acceptOffer(req.params.tripId, driver._id);
    if (!result.ok) {
      const codes = {
        trip_not_found: 404,
        not_offered: 409,
        not_your_offer: 403,
      };
      throw new HttpError(
        codes[result.reason] || 409,
        `Cannot accept offer (${result.reason})`,
      );
    }
    logger.info(`[dispatch] driver=${driver._id} accepted trips=${result.tripIds.length}`);
    res.json({ ok: true, tripIds: result.tripIds });
  } catch (err) {
    next(err);
  }
}

async function rejectOffer(req, res, next) {
  try {
    const driver = await Driver.findOne({ user: req.auth.userId }, { _id: 1 });
    if (!driver) throw new HttpError(404, 'Driver profile not found');

    await dispatchService.rejectOffer(req.params.tripId, driver._id, {
      reason: 'driver_rejected',
    });
    // 204 — backend handles re-dispatch async; client just needs to
    // know the offer is gone from its perspective.
    res.status(204).end();
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
  onboardDriver,
  getMyOffer,
  acceptOffer,
  rejectOffer,
};
