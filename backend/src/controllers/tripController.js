const mongoose = require('mongoose');
const { z } = require('zod');
const Trip = require('../models/Trip');
const Driver = require('../models/Driver');
const MatchGroup = require('../models/MatchGroup');
const User = require('../models/User');
const Unlock = require('../models/Unlock');
const Message = require('../models/Message');
const env = require('../config/env');
const logger = require('../utils/logger');
const { isWithinIndia, distanceKm } = require('../utils/geo');
const { HttpError } = require('../middleware/errorHandler');
const { findMatchForTrip } = require('../services/matchingService');
const { assignDriverForTrip } = require('../services/dispatchService');
const fareService = require('../services/fareService');
const directionsService = require('../services/directionsService');
const {
  broadcastTripUpdate,
  broadcastChatReset,
} = require('../services/notificationService');

// Deep-populate spec: returns the trip with its driver, its match group, and
// for each sibling trip in that group the rider's display name + their own
// pickup/dropoff. This lets the app render real co-rider info on match
// proposals instead of placeholders pointing at the current rider's locations.
const TRIP_POPULATE = [
  { path: 'driver' },
  {
    path: 'matchGroup',
    populate: {
      path: 'trips',
      select: 'rider pickup dropoff status',
      populate: { path: 'rider', select: 'name rating' },
    },
  },
];

const point = z
  .object({
    address: z.string().optional(),
    lat: z.number().min(-90).max(90),
    lng: z.number().min(-180).max(180),
  })
  .refine(isWithinIndia, { message: 'Coordinates must be within India' });

// Sanity-check pickup ↔ drop distance. Rejects the three obvious abuse
// cases: pickup == drop (misclick), too-short ride (<300m, fragmented
// hop), and intercity / inter-region (>100km, not what ShareCab is for).
// Reused by both request and estimate so the rider sees the same error
// at fare preview time as they would at booking.
function refinePickupDropDistance(data, ctx) {
  const km = distanceKm(
    { lat: data.pickup.lat, lng: data.pickup.lng },
    { lat: data.dropoff.lat, lng: data.dropoff.lng },
  );
  if (km < env.trip.minDistanceKm) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ['dropoff'],
      message:
        `Pickup and drop are too close (${km.toFixed(2)} km). ` +
        'ShareCab needs at least ' +
        `${(env.trip.minDistanceKm * 1000).toFixed(0)} m between them.`,
    });
  } else if (km > env.trip.maxDistanceKm) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ['dropoff'],
      message:
        `Trip is too far (${km.toFixed(1)} km). ` +
        `ShareCab is for short city trips up to ${env.trip.maxDistanceKm} km — ` +
        'try a taxi service for intercity rides.',
    });
  }
}

const requestSchema = z
  .object({
    pickup: point,
    dropoff: point,
    shareEnabled: z.boolean().default(true),
  })
  .superRefine(refinePickupDropDistance);

const estimateSchema = z
  .object({
    pickup: point,
    dropoff: point,
  })
  .superRefine(refinePickupDropDistance);

// Parse req.body against a zod schema; on failure throw HttpError(400)
// with the issue messages joined into a single human string. We use
// this everywhere a `.parse()` would otherwise throw raw ZodError —
// raw ZodError has no `.status`, hits the 500 fallthrough, and gets
// serialised as a JSON blob the rider app then renders on its
// searching screen as a wall of red text. The messages are already
// user-facing (custom refines like "Trip is too far…" + "Coordinates
// must be within India") so passing them through verbatim is right.
function parseOrHttp400(schema, body) {
  const parsed = schema.parse ? schema.safeParse(body) : { success: true, data: body };
  if (parsed.success) return parsed.data;
  const issues = parsed.error?.issues || [];
  const messages = issues
    .map((i) => i.message)
    .filter((m) => typeof m === 'string' && m.length > 0);
  const summary = messages.length > 0
    ? messages.join(' · ')
    : 'Invalid request payload';
  throw new HttpError(400, summary, { issues });
}

async function estimate(req, res, next) {
  try {
    const data = parseOrHttp400(estimateSchema, req.body);
    // Get a real road-following distance + duration from Directions.
    // Cached server-side, so repeated estimates on the same stops within
    // 5 min cost one Google API call.
    const r = await directionsService.route([
      { lat: data.pickup.lat, lng: data.pickup.lng },
      { lat: data.dropoff.lat, lng: data.dropoff.lng },
    ]);
    // Vehicle class isn't known pre-dispatch — quote at `sedan` (mid-tier)
    // as the displayed estimate. The actual settlement fare uses the
    // assigned driver's class.
    const solo = fareService.quoteSolo({
      vehicleClass: 'sedan',
      distanceMeters: r.distanceMeters,
      durationSeconds: r.durationSeconds,
    });
    // Optimistic shared estimate: ASSUME a 2-rider group with the same
    // route shape, full share discount, equal split. Real per-rider
    // allocation depends on each rider's solo leg — we can't compute
    // that without an actual second rider.
    const sharedTotalApprox = Math.round(solo.total * (1 - 0.3));
    const sharedEstimate = {
      perRider: Math.round(sharedTotalApprox / 2),
      groupTotal: sharedTotalApprox,
    };
    res.json({
      solo,
      sharedEstimate,
      routingSource: r.source, // 'directions' or 'haversine'
    });
  } catch (err) {
    next(err);
  }
}

async function requestTrip(req, res, next) {
  try {
    const data = parseOrHttp400(requestSchema, req.body);

    // One rider, one in-flight trip. Without this guard a rider can stack
    // multiple `requested` trips by hitting the search button repeatedly,
    // and the matching engine will pull all of them into the same group —
    // which surfaces in the UI as phantom co-riders that don't exist.
    const existing = await Trip.findOne({
      rider: req.auth.userId,
      status: { $in: ['requested', 'matched', 'driver_assigned', 'arriving', 'in_progress'] },
    }, { _id: 1, status: 1 });
    if (existing) {
      throw new HttpError(
        409,
        `You already have an active trip (${existing.status}). Cancel it before starting a new one.`,
      );
    }

    // No upfront unlock gate. Trip creation is always free — the rider
    // only pays (ads OR Razorpay) AFTER a co-rider match is confirmed
    // (see `unlockMatch`). The earlier "pay upfront" model was hostile
    // UX: it charged riders for a search that might never find a
    // co-rider, which is the textbook dead-money problem.
    //
    // Solo trips (shareEnabled=false): no unlock ever — there's no
    // sharing benefit to pay for.
    // Solo fallback after a shared search times out without a co-rider:
    // also no unlock — the rider didn't get the benefit they were
    // searching for.

    // 4-digit pickup OTP. Server-generated so the value isn't forgeable
    // client-side — the driver enters it from the rider's screen when
    // arriving at this rider's pickup stop. Crypto-grade randomness
    // overkill for a 4-digit space but the call is cheap.
    const otp = Math.floor(1000 + Math.random() * 9000).toString();

    // Solo trips dispatch immediately and skip the Find Cab gate —
    // there's no co-rider to wait for. Shared trips create with the
    // gate closed; both riders must tap Find Cab before dispatch.
    const trip = await Trip.create({
      rider: req.auth.userId,
      shareEnabled: data.shareEnabled,
      pickup: {
        address: data.pickup.address,
        location: { type: 'Point', coordinates: [data.pickup.lng, data.pickup.lat] },
      },
      dropoff: {
        address: data.dropoff.address,
        location: { type: 'Point', coordinates: [data.dropoff.lng, data.dropoff.lat] },
      },
      otp,
      readyToFindCab: !data.shareEnabled,
    });

    // Fare estimate stored upfront for the rider's reference. Pre-
    // dispatch we don't know the assigned driver's vehicle class — quote
    // at sedan (mid-tier) and re-quote at settlement using the actual
    // class. Caches Directions for 5 min so this is cheap on retries.
    const routing = await directionsService.route([
      { lat: data.pickup.lat, lng: data.pickup.lng },
      { lat: data.dropoff.lat, lng: data.dropoff.lng },
    ]);
    const fare = fareService.quoteSolo({
      vehicleClass: 'sedan',
      distanceMeters: routing.distanceMeters,
      durationSeconds: routing.durationSeconds,
    });
    trip.fareEstimate = fare.total;          // paise
    trip.distanceKm = fare.distanceKm;
    trip.durationMin = fare.durationMin;
    trip.fareBreakdown = fare;               // structured breakdown for UI + audit
    await trip.save();

    // Match-then-dispatch.
    //
    // For shareEnabled trips with no immediate match, we DEFER solo dispatch by
    // env.match.dispatchDelayMs. This gives a co-rider arriving moments later
    // a chance to pair via findMatchForTrip — without the delay, the first
    // rider gets locked to a driver before the second rider's request lands,
    // and they never group up.
    //
    // The deferred callback re-checks status before doing anything, so it
    // self-cancels if the trip was matched, cancelled, or otherwise advanced
    // during the wait.
    if (data.shareEnabled) {
      const group = await findMatchForTrip(trip._id);
      if (group) {
        // Deferred dispatch in BOTH modes now. Previously driver-dispatch
        // immediately offered the trip to a driver here — but with the
        // upfront unlock removed, we'd be committing a driver's time
        // before the rider has paid for the sharing benefit. Instead:
        // status='matched', rider sees the match-result screen, taps
        // unlock, and `unlockMatch` triggers `offerGroupToDriver`. In
        // rider-only mode there's no dispatch step at all — same as
        // before.
        //
        // No-op: the matching service already set status='matched' on
        // every member trip when the group was formed.
      } else {
        scheduleDeferredDispatch(trip._id);
      }
    } else if (!env.match.riderOnly) {
      // Solo dispatch only when drivers exist. In rider-only mode a
      // solo (shareEnabled: false) trip has nothing to do — the rider
      // is just arranging their own cab. We leave the trip in
      // 'requested' state; the deferred cleanup tidies it up.
      await assignDriverForTrip(trip);
    } else {
      // rider-only AND shareEnabled=false: nothing to match against,
      // nothing to dispatch. Cancel immediately so we don't leave the
      // trip dangling.
      trip.status = 'cancelled';
      trip.cancelledAt = new Date();
      trip.cancelReason = 'rider-only:solo-not-supported';
      await trip.save();
    }

    const refreshed = await Trip.findById(trip._id).populate(TRIP_POPULATE);
    await broadcastTripUpdate(refreshed);

    res.status(201).json({ trip: refreshed });
  } catch (err) {
    next(err);
  }
}

function scheduleDeferredDispatch(tripId) {
  setTimeout(async () => {
    try {
      const trip = await Trip.findById(tripId);
      // Self-cancel: trip may have already been matched/cancelled/dispatched
      // by another path during the wait window.
      if (!trip || trip.status !== 'requested') return;

      const group = await findMatchForTrip(trip._id);
      if (group) {
        // Match formed during the deferred window. Do NOT auto-fire
        // dispatch — the matching service has already set every
        // sibling's status to 'matched', and the riders' Find Cab gate
        // is what triggers the offer to a driver. Previously we called
        // `assignDriverForGroup` here, which bypassed the gate and
        // committed a driver before either rider had a chance to tap
        // Find Cab. Now we just broadcast so the riders' polling
        // watchers see the match and surface the Find Cab CTA.
        const refreshed = await Trip.findById(tripId).populate(TRIP_POPULATE);
        await broadcastTripUpdate(refreshed);
      } else {
        // Window elapsed without a co-rider — auto-cancel the trip so it
        // stops showing up as a candidate for future rider searches. Without
        // this, abandoned trips accumulate in `requested` state and get
        // pulled into unrelated match groups (manifests as phantom riders
        // in the UI). The rider's app sees this via its own polling
        // watcher; the screen surfaces the empty-state UI off its own timer.
        trip.status = 'cancelled';
        trip.cancelledAt = new Date();
        trip.cancelReason = 'search-window-expired';
        await trip.save();
        if (trip.matchGroup) {
          const grp = await MatchGroup.findById(trip.matchGroup);
          if (grp) {
            grp.trips = grp.trips.filter(
              (t) => t.toString() !== trip._id.toString(),
            );
            if (grp.trips.length === 0) grp.status = 'cancelled';
            await grp.save();
          }
        }
        logger.info(`Trip ${tripId}: search window expired without a match; auto-cancelled.`);
        await broadcastTripUpdate(trip);
      }
    } catch (err) {
      logger.error(`Deferred dispatch failed for trip ${tripId}: ${err.message}`);
    }
  }, env.match.dispatchDelayMs);
}

async function getTrip(req, res, next) {
  try {
    const trip = await Trip.findById(req.params.id).populate(TRIP_POPULATE);
    if (!trip) throw new HttpError(404, 'Trip not found');
    if (
      trip.rider.toString() !== req.auth.userId &&
      req.auth.role !== 'admin' &&
      req.auth.role !== 'driver'
    ) {
      throw new HttpError(403, 'Forbidden');
    }

    // Rider-only redaction: until the requesting rider has unlocked
    // their match, hide the sibling trips' rider info + exact stops.
    // The match group itself stays visible (so the client knows a match
    // exists), but co-rider names, ratings, pickups and drops are
    // stripped. Admin / driver fetches always see the full doc.
    // Redact co-rider details until the rider unlocks the match. Fires
    // in BOTH modes now (driver-dispatch was previously auto-revealed
    // because the unlock was consumed at request time). The rider's
    // MatchUnlockSheet uses the redaction signal (`gatedUnlock` flag on
    // the proposal) to decide when to show ads/pay.
    const redact =
      req.auth.role !== 'admin' &&
      req.auth.role !== 'driver' &&
      trip.rider.toString() === req.auth.userId &&
      !trip.matchRevealedAt &&
      // Only meaningful once siblings exist — bare requested/solo trips
      // have nothing to redact.
      Boolean(trip.matchGroup);
    if (redact) {
      const obj = trip.toObject();
      if (obj.matchGroup && Array.isArray(obj.matchGroup.trips)) {
        obj.matchGroup.trips = obj.matchGroup.trips.map((sibling) => {
          if (String(sibling._id) === String(trip._id)) return sibling;
          // Keep id + status so the client can render "X co-riders
          // matched" without leaking identity. Everything else gone.
          return {
            _id: sibling._id,
            status: sibling.status,
            redacted: true,
          };
        });
      }
      return res.json({ trip: obj });
    }
    res.json({ trip });
  } catch (err) {
    next(err);
  }
}

// Rider-only mode: close this trip ourselves. In driver-dispatch mode
// trip completion is owned by the driver (`dropOffRider`). In rider-
// only mode there's no driver, so the rider self-completes once
// they've met / arranged their own cab off-platform. Endpoint only
// works when MATCH_RIDER_ONLY is on, to keep driver mode unambiguous.
//
// Marks this rider's trip as completed with fareFinal=0 (no platform
// fare to settle — they paid their cab provider directly). If they're
// in a matched group, settles the group when the last sibling closes
// too, mirroring `dropOffRider`'s group lifecycle.
async function riderCloseTrip(req, res, next) {
  try {
    const trip = await Trip.findById(req.params.id);
    if (!trip) throw new HttpError(404, 'Trip not found');
    if (trip.rider.toString() !== req.auth.userId) {
      throw new HttpError(403, 'Not your trip');
    }
    // Gate on per-trip state, not the global env flag. A trip without a
    // driver is always rider-closable (rider arranged transport off
    // platform, no fare to settle). A trip WITH a driver needs the
    // driver-aware /end-early path so the driver gets paid for the
    // committed run. Previously this just checked env.match.riderOnly,
    // which broke whenever a rider-only trip outlived a flag flip.
    if (trip.driver) {
      throw new HttpError(
        409,
        'This trip has a driver assigned. Use /trips/:id/end-early to ' +
          'stop the ride here (full fare), or /cancel before pickup.',
      );
    }
    // Idempotent: closing a closed trip returns the doc without changes.
    if (trip.status === 'completed' || trip.status === 'cancelled') {
      return res.json({ trip, alreadyClosed: true });
    }
    // Only matched / arriving / in-progress trips are sensible to close.
    // Pre-match (requested) trips should be cancelled, not closed.
    const closable = ['matched', 'driver_assigned', 'arriving', 'in_progress'];
    if (!closable.includes(trip.status)) {
      throw new HttpError(
        409,
        `Cannot close from status ${trip.status}. Cancel instead if you haven't matched yet.`,
      );
    }

    const now = new Date();
    trip.status = 'completed';
    trip.completedAt = now;
    // Mark startedAt at close time when nothing else set it. In
    // rider-only mode there's no driver pickUpRider step to set it,
    // so without this every rider-only close would silently fail the
    // rating-eligibility gate (`startedAt != null`) and never trigger
    // the co-rider rating prompt. The riders coordinated their cab
    // off-platform; we don't know exactly when they actually started
    // moving, but the close itself is the canonical "this ride
    // happened" signal in this mode.
    if (!trip.startedAt) trip.startedAt = now;
    // No driver to charge → no platform fare. The rider paid their
    // off-platform cab (Uber / Ola / etc.) directly; ShareCab only
    // facilitated the match.
    trip.fareFinal = 0;
    await trip.save();

    // Bump this rider's totalRides — they completed a coordinated ride
    // through us even if no driver was on platform.
    await User.updateOne({ _id: trip.rider }, { $inc: { totalRides: 1 } });

    // Group bookkeeping: when every sibling has closed, mark the
    // match group completed too. Mirror of dropOffRider's logic.
    if (trip.matchGroup) {
      const group = await MatchGroup.findById(trip.matchGroup).populate('trips');
      const allDone = group.trips.every((t) => t.status === 'completed');
      if (allDone) {
        group.status = 'completed';
        await group.save();
      }
    }

    await broadcastTripUpdate(trip);
    res.json({ trip });
  } catch (err) {
    next(err);
  }
}

// =============================================================================
// Rider-initiated early end — driver-dispatch mode.
//
// "Stop the ride here" while in_progress. The rider drops out at the
// current location; the platform charges the FULL pre-quoted fare (no
// proration). Justification for the no-refund rule:
//   - The driver is already committed and was on the planned route.
//   - The fare was quoted up-front so the rider knew the cost; ending
//     early is the rider's convenience, not the driver's fault.
//   - Mid-trip proration invites abuse ("end at 90% to save 10%").
//
// For shared trips: only this rider's slice ends. Siblings stay in_progress
// and the driver continues to their drops. Pulled from Driver.activeTrips
// so the driver's UI surfaces "one rider dropped off, n-1 remaining."
// =============================================================================
async function endRideEarly(req, res, next) {
  try {
    const trip = await Trip.findById(req.params.id);
    if (!trip) throw new HttpError(404, 'Trip not found');
    if (trip.rider.toString() !== req.auth.userId) {
      throw new HttpError(403, 'Not your trip');
    }
    // Idempotent: a previously-ended trip returns its existing state.
    if (trip.status === 'completed' || trip.status === 'cancelled') {
      return res.json({ trip, alreadyEnded: true });
    }
    // Only sensible for trips that have actually started. Pre-pickup
    // → /trips/:id/cancel (no charge). Anything else is a programmer
    // error; reject with 409 so the bug surfaces in the client.
    if (trip.status !== 'in_progress') {
      throw new HttpError(
        409,
        `Cannot end-early from status ${trip.status}. ` +
          'Use /cancel before pickup; /end-early only applies to in_progress.',
      );
    }

    const now = new Date();
    trip.status = 'completed';
    trip.completedAt = now;
    // FULL pre-quoted fare. fareEstimate is already in paise from the
    // pricing rewrite + already accounts for the rider's allocation in
    // shared trips (the share was set when the match formed).
    trip.fareFinal = trip.fareEstimate;
    await trip.save();

    // Pull THIS trip from the driver's activeTrips. Siblings stay so
    // the driver's UI keeps showing the remaining riders.
    if (trip.driver) {
      await Driver.updateOne(
        { _id: trip.driver },
        { $pull: { activeTrips: trip._id } },
      );
    }

    // Bump totalRides — the rider did complete a ride, just shorter.
    await User.updateOne({ _id: trip.rider }, { $inc: { totalRides: 1 } });

    // Group bookkeeping: when every sibling completes, the group is done.
    if (trip.matchGroup) {
      const group = await MatchGroup.findById(trip.matchGroup).populate('trips');
      const allDone = group.trips.every((t) => t.status === 'completed');
      if (allDone) {
        group.status = 'completed';
        await group.save();
      }
    }

    logger.info(
      `[trip] early-end rider=${trip.rider} driver=${trip.driver || 'n/a'} ` +
      `trip=${trip._id} fareFinal=${trip.fareFinal} paise`,
    );

    await broadcastTripUpdate(trip);
    res.json({ trip });
  } catch (err) {
    next(err);
  }
}

// Consume an unlock to reveal co-rider details on a matched trip.
// Decoupled from dispatch: revealing the match doesn't commit to a
// driver. The rider sees the co-rider details, then has to explicitly
// tap "Find Cab" (POST /trips/:id/find-cab) before dispatch fires.
// Both riders in a shared group must tap Find Cab before any driver
// gets an offer.
//
// Idempotent: once matchRevealedAt is set, repeat calls return the
// populated trip without consuming another unlock. Returns 402 when the
// rider has no usable unlock, 409 when there's no match to unlock yet.
async function unlockMatch(req, res, next) {
  try {
    const trip = await Trip.findById(req.params.id);
    if (!trip) throw new HttpError(404, 'Trip not found');
    if (trip.rider.toString() !== req.auth.userId) {
      throw new HttpError(403, 'Not your trip');
    }
    if (!trip.matchGroup) {
      throw new HttpError(409, 'No match to unlock yet');
    }
    if (trip.matchRevealedAt) {
      // Already unlocked — return populated trip without consuming.
      const populated = await Trip.findById(trip._id).populate(TRIP_POPULATE);
      return res.json({ trip: populated, alreadyUnlocked: true });
    }

    const now = new Date();
    const unlock = await Unlock.findOneAndUpdate(
      { rider: req.auth.userId, usedAt: null, expiresAt: { $gt: now } },
      { $set: { usedAt: now, usedForTrip: trip._id } },
      { sort: { expiresAt: 1 } },
    );
    if (!unlock) {
      throw new HttpError(
        402,
        'Matching gate not unlocked: complete 2 rewarded ads or pay to unlock',
      );
    }

    trip.matchRevealedAt = now;
    await trip.save();

    // Dispatch is NOT triggered here anymore. The rider now sees
    // revealed co-rider details + the Find Cab CTA; dispatch waits
    // until both riders explicitly opt in (POST /:id/find-cab). This
    // avoids the old race where one rider's unlock would commit a
    // driver while the co-rider was still deciding.

    const populated = await Trip.findById(trip._id).populate(TRIP_POPULATE);
    res.json({ trip: populated });
  } catch (err) {
    next(err);
  }
}

// Rider taps Find Cab → mark this trip ready to dispatch. When every
// trip in the matchGroup is ready, hand the group to the dispatch
// service. Solo trips skip this gate entirely; they're created with
// readyToFindCab=true and dispatched in `requestTrip`.
//
// Idempotent: a second call from the same rider is a no-op success.
// Returns the populated trip so the rider's UI can show the
// "waiting for co-rider..." state if siblings haven't tapped yet.
async function findCab(req, res, next) {
  try {
    const trip = await Trip.findById(req.params.id);
    if (!trip) throw new HttpError(404, 'Trip not found');
    if (trip.rider.toString() !== req.auth.userId) {
      throw new HttpError(403, 'Not your trip');
    }
    // Only meaningful for `matched` trips: pre-match the rider hasn't
    // even seen a co-rider yet, and post-dispatch (offered /
    // driver_assigned / arriving / in_progress / completed / cancelled)
    // the gate has either fired or is no longer relevant. Anything else
    // is a programmer error in the client; surface as 409.
    if (trip.status !== 'matched') {
      throw new HttpError(
        409,
        `Cannot find-cab from status ${trip.status}. Only matched trips have the gate.`,
      );
    }

    // Mark this rider ready. We persist via $set so concurrent siblings
    // tapping at the same time don't clobber each other.
    if (!trip.readyToFindCab) {
      trip.readyToFindCab = true;
      await trip.save();
    }

    // In rider-only mode there's no dispatch step — the gate is just a
    // synchronisation primitive. Return the populated trip so the
    // riders' screens can transition together.
    if (env.match.riderOnly) {
      const populated = await Trip.findById(trip._id).populate(TRIP_POPULATE);
      return res.json({ trip: populated });
    }

    // Driver-dispatch mode: check if every sibling is ready. If yes,
    // fire the offer. Best-effort — the offer may not find a driver,
    // in which case the trips stay matched and the deferred-dispatch
    // path retries.
    if (trip.matchGroup) {
      const group = await MatchGroup.findById(trip.matchGroup);
      if (group && !group.driver) {
        // Count readiness via a focused projection instead of populating
        // group.trips. dispatchService.offerGroupToDriver expects
        // group.trips to be plain ObjectIds (it uses them in $in queries
        // and as setTimeout keys) — handing it a populated group would
        // collapse every offer-expiry timer key to "[object Object]"
        // and break re-dispatch.
        const readyCount = await Trip.countDocuments({
          _id: { $in: group.trips },
          readyToFindCab: true,
        });
        if (readyCount === group.trips.length) {
          try {
            const dispatchService = require('../services/dispatchService');
            await dispatchService.offerGroupToDriver(group);
          } catch (e) {
            logger.warn(`[find-cab] dispatch failed group=${group._id}: ${e.message}`);
          }
        }
      }
    }

    const populated = await Trip.findById(trip._id).populate(TRIP_POPULATE);
    res.json({ trip: populated });
  } catch (err) {
    next(err);
  }
}

async function listMyTrips(req, res, next) {
  try {
    const trips = await Trip.find({ rider: req.auth.userId })
      .sort({ createdAt: -1 })
      .limit(50);
    res.json({ trips });
  } catch (err) {
    next(err);
  }
}

// Recent destinations the rider has dropped at, deduped by coords so
// repeat trips to "home" / "office" collapse to a single entry. We round
// to 4 decimals (~10m precision) — tight enough that two different
// buildings on the same street stay separate, loose enough that one
// rooftop pin coming from Places autocomplete vs another doesn't
// fragment the list.
//
// Implementation uses an aggregation so we can dedup + sort + cap in
// one round-trip. The client uses this as a tap-to-set-destination
// shortcut on the destination screen — first-time users see an empty
// state and pick via the map as usual.
async function getRecentDestinations(req, res, next) {
  try {
    const limit = Math.min(
      Math.max(parseInt(req.query.limit || '5', 10) || 5, 1),
      20,
    );
    const rows = await Trip.aggregate([
      {
        $match: {
          rider: new mongoose.Types.ObjectId(req.auth.userId),
          // Only completed trips → no half-formed / cancelled rides
          // pollute the list. A user who repeatedly cancelled the same
          // destination probably doesn't want it back as a shortcut.
          status: 'completed',
          'dropoff.location.coordinates': { $exists: true, $ne: [] },
        },
      },
      // Bucket by rounded lat/lng so close-by drops collapse together.
      {
        $project: {
          createdAt: 1,
          address: { $ifNull: ['$dropoff.address', ''] },
          lat: { $arrayElemAt: ['$dropoff.location.coordinates', 1] },
          lng: { $arrayElemAt: ['$dropoff.location.coordinates', 0] },
        },
      },
      {
        $project: {
          createdAt: 1,
          address: 1,
          lat: 1,
          lng: 1,
          // 4-decimal rounding via $round → bucket key.
          latKey: { $round: ['$lat', 4] },
          lngKey: { $round: ['$lng', 4] },
        },
      },
      {
        $group: {
          _id: { latKey: '$latKey', lngKey: '$lngKey' },
          // Take the most-recent representative for address + exact coords.
          address: { $last: '$address' },
          lat: { $last: '$lat' },
          lng: { $last: '$lng' },
          lastUsedAt: { $max: '$createdAt' },
          tripCount: { $sum: 1 },
        },
      },
      { $sort: { lastUsedAt: -1 } },
      { $limit: limit },
    ]);

    res.json({
      destinations: rows.map((r) => ({
        address: r.address,
        lat: r.lat,
        lng: r.lng,
        lastUsedAt: r.lastUsedAt,
        tripCount: r.tripCount,
      })),
    });
  } catch (err) {
    next(err);
  }
}

// Statuses that count as an "in-flight" trip for the rider — anything still
// resolvable. Completed/cancelled trips are NOT considered active.
const ACTIVE_TRIP_STATUSES = ['requested', 'matched', 'driver_assigned', 'arriving', 'in_progress'];

async function getMyActiveTrip(req, res, next) {
  try {
    const trip = await Trip.findOne({
      rider: req.auth.userId,
      status: { $in: ACTIVE_TRIP_STATUSES },
    })
      .sort({ createdAt: -1 })
      .populate(TRIP_POPULATE);
    if (!trip) {
      // 200 with null is friendlier than 404 — clients want to call this on
      // every cold start; an explicit "no active trip" is a happy outcome.
      return res.json({ trip: null });
    }
    res.json({ trip });
  } catch (err) {
    next(err);
  }
}

async function cancelTrip(req, res, next) {
  try {
    const trip = await Trip.findById(req.params.id);
    if (!trip) throw new HttpError(404, 'Trip not found');
    if (trip.rider.toString() !== req.auth.userId) throw new HttpError(403, 'Forbidden');
    if (['completed', 'cancelled'].includes(trip.status)) {
      throw new HttpError(400, `Cannot cancel a ${trip.status} trip`);
    }

    // Captured BEFORE we mutate the trip so the rating recompute below
    // sees the post-cancel state. Penalty applies only when the rider
    // had explicitly committed (Find Cab pressed, or solo trip created
    // with shareEnabled=false which is auto-committed). Pre-commit
    // cancels are exploratory and don't touch driver supply.
    const wasCommitted = trip.readyToFindCab === true;

    trip.status = 'cancelled';
    trip.cancelledAt = new Date();
    trip.cancelReason = req.body?.reason;
    await trip.save();

    // 1. Pull this trip out of the assigned driver's activeTrips list.
    //    Without this, a driver who completed the *other* sibling trips would
    //    still appear "busy" because the cancelled trip lingers in the array.
    if (trip.driver) {
      await Driver.updateOne(
        { _id: trip.driver },
        { $pull: { activeTrips: trip._id } },
      );
    }

    // 2. Update / dissolve the match group + wipe chat history (privacy:
    //    a future joiner shouldn't see the leaver's conversation).
    if (trip.matchGroup) {
      const group = await MatchGroup.findById(trip.matchGroup);
      if (group) {
        group.trips = group.trips.filter((t) => t.toString() !== trip._id.toString());
        if (group.trips.length === 0) {
          // Last rider left — cancel the group and release the driver entirely.
          group.status = 'cancelled';
          if (group.driver) {
            await Driver.updateOne(
              { _id: group.driver },
              { $set: { activeTrips: [] } },
            );
          }
        }
        await group.save();
      }

      // Composition changed → wipe the chat and tell remaining riders'
      // clients to clear their local cache. Awaited so we don't ack the
      // cancel before chat state is consistent.
      await Message.deleteMany({ matchGroup: trip.matchGroup });
      await broadcastChatReset(trip.matchGroup);
    }

    await broadcastTripUpdate(trip);

    // Apply the -0.1 cancel penalty when the rider had committed
    // (Find Cab pressed, or solo auto-commit). recomputeUserRating
    // re-derives the score from scratch — Rating avg, RatingSkip
    // count, and the now-incremented cancel count — so repeat cancels
    // accumulate naturally with no risk of double-applying. Failures
    // here are non-fatal: the cancel itself succeeded above, the
    // recompute is a side effect. Lazy-required to dodge the circular
    // ratingController → Trip → tripController boot dependency.
    if (wasCommitted) {
      try {
        const { recomputeUserRating } = require('./ratingController');
        await recomputeUserRating(req.auth.userId);
      } catch (e) {
        logger.warn(`[cancel-penalty] recompute failed user=${req.auth.userId}: ${e.message}`);
      }
    }
    res.json({ trip });
  } catch (err) {
    next(err);
  }
}

async function getGroupFare(req, res, next) {
  try {
    const group = await MatchGroup.findById(req.params.id).populate('trips');
    if (!group) throw new HttpError(404, 'Match group not found');

    // Resolve vehicle class from the dispatched driver (if any). For a
    // pre-dispatch group quote, default to sedan — same convention as
    // the solo `estimate` endpoint.
    let vehicleClass = 'sedan';
    if (group.driver) {
      const driver = await Driver.findById(group.driver);
      if (driver?.vehicle?.capacity != null) {
        vehicleClass = fareService.classifyByCapacity(driver.vehicle.capacity);
      }
    }

    // Use Directions per member for the time component (heavy-traffic
    // detection); cache makes this cheap on retries.
    const members = await Promise.all(group.trips.map(async (t) => {
      const r = await directionsService.route([
        { lat: t.pickup.location.coordinates[1], lng: t.pickup.location.coordinates[0] },
        { lat: t.dropoff.location.coordinates[1], lng: t.dropoff.location.coordinates[0] },
      ]);
      return {
        tripId: t._id.toString(),
        distanceMeters: r.distanceMeters,
        durationSeconds: r.durationSeconds,
      };
    }));
    const fare = fareService.quoteShared({ vehicleClass, members });
    res.json({ group, fare });
  } catch (err) {
    next(err);
  }
}

async function loadDriverTrip(req) {
  const driver = await Driver.findOne({ user: req.auth.userId });
  if (!driver) throw new HttpError(404, 'Driver profile not found');
  const trip = await Trip.findById(req.params.id);
  if (!trip) throw new HttpError(404, 'Trip not found');
  if (!trip.driver || trip.driver.toString() !== driver._id.toString()) {
    throw new HttpError(403, 'Not your trip');
  }
  return { driver, trip };
}

function tripScopeFilter(trip) {
  return trip.matchGroup ? { matchGroup: trip.matchGroup } : { _id: trip._id };
}

async function arriveTrip(req, res, next) {
  try {
    const { trip } = await loadDriverTrip(req);
    if (trip.status !== 'driver_assigned') {
      throw new HttpError(400, `Cannot arrive from status ${trip.status}`);
    }
    const filter = tripScopeFilter(trip);
    await Trip.updateMany(filter, { $set: { status: 'arriving' } });
    const trips = await Trip.find(filter).populate('driver matchGroup');
    res.json({ trips });
  } catch (err) {
    next(err);
  }
}

// Per-rider pickup. The driver hits this when they reach a specific
// rider's pickup point (their app's geofence banner surfaces the right
// rider so they don't have to think about it). Advances ONLY this trip
// from `arriving` → `in_progress`; siblings are unaffected. The first
// pickup in a group also flips the group's status to `in_progress`.
async function pickUpRider(req, res, next) {
  try {
    const { trip } = await loadDriverTrip(req);
    if (trip.status !== 'arriving') {
      throw new HttpError(
        400,
        `Cannot mark picked up from status ${trip.status}`,
      );
    }

    // OTP gate. The rider shows the driver a 4-digit code; the driver
    // types it in to confirm they're picking up the correct passenger.
    // Per-trip OTPs mean a co-rider's code can't accidentally pick up
    // the wrong rider. Skipped only when the trip predates the OTP
    // column entirely (legacy data) so the suite stays green during
    // the rollout window — once trip.otp is populated, it's enforced.
    if (trip.otp) {
      const otp = typeof req.body?.otp === 'string'
        ? req.body.otp.trim()
        : '';
      if (otp.length === 0) {
        throw new HttpError(400, 'OTP required to confirm pickup');
      }
      if (otp !== trip.otp) {
        throw new HttpError(400, 'Wrong OTP. Ask the rider to check.');
      }
    }

    const now = new Date();
    trip.status = 'in_progress';
    trip.startedAt = trip.startedAt || now;

    // Capture actual GPS when the driver app sent it. Optional + validated
    // through the same India-bounds schema as request-time coords. Older
    // driver-app builds that don't send coords leave actualPickup null;
    // the rider-side map falls back to the requested pickup pin.
    const coords = parseActualCoords(req.body);
    if (coords) {
      trip.actualPickup = {
        location: { type: 'Point', coordinates: [coords.lng, coords.lat] },
        recordedAt: now,
      };
    }
    await trip.save();

    if (trip.matchGroup) {
      // Promote the group to `in_progress` on the FIRST pickup so the
      // rider-side UI can switch from "driver arriving" to "in cab".
      // Subsequent pickups are no-ops at the group level.
      await MatchGroup.updateOne(
        { _id: trip.matchGroup, status: { $in: ['sealed', 'forming'] } },
        { $set: { status: 'in_progress' } },
      );
    }

    await broadcastTripUpdate(trip);
    const trips = await Trip.find(tripScopeFilter(trip))
      .populate('driver matchGroup');
    res.json({ trips });
  } catch (err) {
    next(err);
  }
}

// Per-rider dropoff. The driver hits this when they reach a specific
// rider's destination. Advances ONLY this trip from `in_progress` →
// `completed`, settles their fare, and pulls them from the driver's
// activeTrips. When the LAST sibling's trip completes, the group
// settles + the driver's totalRides counter increments (one drive,
// one count, regardless of how many riders shared the cab).
async function dropOffRider(req, res, next) {
  try {
    const { driver, trip } = await loadDriverTrip(req);
    if (trip.status !== 'in_progress') {
      throw new HttpError(
        400,
        `Cannot mark dropped from status ${trip.status}`,
      );
    }
    const now = new Date();

    // Capture actual drop GPS. Mirrors the pickup capture in pickUpRider —
    // older driver apps that omit coords leave the field null.
    const dropCoords = parseActualCoords(req.body);
    if (dropCoords) {
      trip.actualDropoff = {
        location: { type: 'Point', coordinates: [dropCoords.lng, dropCoords.lat] },
        recordedAt: now,
      };
    }

    // Settle this rider's fare. Shared trips: re-quote with the driver's
    // actual vehicle class and allocate proportionally to each rider's
    // solo leg (longer leg → higher share). Solo: keep the estimate.
    let fareFinal = trip.fareEstimate;
    let fareBreakdown = trip.fareBreakdown;
    if (trip.matchGroup) {
      const group = await MatchGroup.findById(trip.matchGroup).populate('trips');
      if (group && group.trips.length > 0) {
        const vehicleClass = driver.vehicle?.capacity != null
          ? fareService.classifyByCapacity(driver.vehicle.capacity)
          : 'sedan';
        const members = await Promise.all(group.trips.map(async (t) => {
          const r = await directionsService.route([
            { lat: t.pickup.location.coordinates[1], lng: t.pickup.location.coordinates[0] },
            { lat: t.dropoff.location.coordinates[1], lng: t.dropoff.location.coordinates[0] },
          ]);
          return {
            tripId: t._id.toString(),
            distanceMeters: r.distanceMeters,
            durationSeconds: r.durationSeconds,
          };
        }));
        const groupFare = fareService.quoteShared({ vehicleClass, members });
        const mine = groupFare.allocations.find((a) => a.tripId === trip._id.toString());
        if (mine) {
          fareFinal = mine.total;
          fareBreakdown = mine;
        }
      }
    }

    trip.status = 'completed';
    trip.completedAt = now;
    trip.fareFinal = fareFinal;
    trip.fareBreakdown = fareBreakdown;
    await trip.save();

    // This rider is no longer in the cab — pull from activeTrips. We
    // don't blow away the whole activeTrips list because siblings may
    // still be in-cab (and the driver-home dispatch card needs them).
    await Driver.updateOne(
      { _id: driver._id },
      { $pull: { activeTrips: trip._id } },
    );
    // Bump THIS rider's count immediately; their journey is done.
    await User.updateOne({ _id: trip.rider }, { $inc: { totalRides: 1 } });

    if (trip.matchGroup) {
      const group = await MatchGroup.findById(trip.matchGroup).populate('trips');
      const allDone = group.trips.every((t) => t.status === 'completed');
      if (allDone) {
        group.status = 'completed';
        await group.save();
        // One drive = +1 to the driver's counter, regardless of rider count.
        await User.updateOne({ _id: driver.user }, { $inc: { totalRides: 1 } });
      }
    } else {
      // Solo dispatch — driver's drive ends with this single dropoff.
      await User.updateOne({ _id: driver.user }, { $inc: { totalRides: 1 } });
    }

    await broadcastTripUpdate(trip);
    const trips = await Trip.find(tripScopeFilter(trip))
      .populate('driver matchGroup');
    res.json({ trips });
  } catch (err) {
    next(err);
  }
}

// Validate optional `{ lat, lng }` from a pickup/drop body. Returns the
// coords when present and within India; returns null when absent, throws
// on malformed values so the driver app gets a clear 400. Reused by
// pickUpRider + dropOffRider so the validation behaviour is identical.
const actualCoordsSchema = z
  .object({
    lat: z.number().min(-90).max(90),
    lng: z.number().min(-180).max(180),
  })
  .refine(isWithinIndia, { message: 'Coordinates must be within India' })
  .nullable();

function parseActualCoords(body) {
  if (!body || (body.lat == null && body.lng == null)) return null;
  // actualPickup / actualDropoff is an OPTIONAL observability capture —
  // it lets the rider's map snap pins to the actual cab position, and
  // the driver-side audit see "you ended at the right place." It is
  // NOT trip-critical: missing values just mean we didn't record them.
  //
  // So invalid coords (NaN, out-of-India sim GPS, GPS glitch in a
  // tunnel) should be DROPPED, not blocked. Previously this threw a
  // raw ZodError → fell through to 500; my earlier fix turned it into
  // a 400 which still blocks the pickup/drop transition. Both wrong
  // for an optional capture. safeParse + return null is the right
  // behaviour: log it so the telemetry is visible, then move on.
  //
  // Common dev trigger: iOS sims default to Cupertino. Real drivers in
  // India never hit this path.
  const result = actualCoordsSchema.safeParse({
    lat: Number(body.lat),
    lng: Number(body.lng),
  });
  if (!result.success) {
    logger.warn(
      `[parseActualCoords] dropping out-of-bounds coords lat=${body.lat} lng=${body.lng}`,
    );
    return null;
  }
  return result.data;
}

// =============================================================================
// Live driver location + ETA for the rider's map.
//
// Rider's RideStatusScreen polls this every 5 seconds during the
// arriving + in_progress states. We expose just the data the rider needs:
//   - driver's current coords + when they were last updated
//   - ETA seconds + distance to the next pending stop (pickup or drop)
//
// Rider must own the trip OR be a co-rider in its matchGroup. Returns
// 404 when no driver is assigned yet (rider-only mode, or pre-dispatch).
// =============================================================================
async function getDriverLocation(req, res, next) {
  try {
    const trip = await Trip.findById(req.params.id);
    if (!trip) throw new HttpError(404, 'Trip not found');

    // Authorization: rider on the trip, or a co-rider in the same group.
    const isOwner = trip.rider.toString() === req.auth.userId;
    let isCoRider = false;
    if (!isOwner && trip.matchGroup) {
      const siblings = await Trip.find(
        { matchGroup: trip.matchGroup, rider: req.auth.userId },
        { _id: 1 },
      ).lean();
      isCoRider = siblings.length > 0;
    }
    if (!isOwner && !isCoRider) {
      throw new HttpError(403, 'Not your trip');
    }

    if (!trip.driver) {
      throw new HttpError(404, 'No driver assigned yet');
    }
    const driver = await Driver.findById(trip.driver);
    if (!driver) throw new HttpError(404, 'Driver not found');
    if (!driver.currentLocation?.coordinates?.length) {
      throw new HttpError(404, "Driver hasn't reported a location yet");
    }
    const driverPos = {
      lat: driver.currentLocation.coordinates[1],
      lng: driver.currentLocation.coordinates[0],
    };

    // ETA target depends on which leg we're on. driver_assigned + arriving
    // → ETA to pickup. in_progress → ETA to drop. Any other status →
    // omit ETA (the rider isn't actively tracking).
    let etaTarget = null;
    if (trip.status === 'driver_assigned' || trip.status === 'arriving') {
      etaTarget = {
        toStop: 'pickup',
        coords: {
          lat: trip.pickup.location.coordinates[1],
          lng: trip.pickup.location.coordinates[0],
        },
      };
    } else if (trip.status === 'in_progress') {
      etaTarget = {
        toStop: 'dropoff',
        coords: {
          lat: trip.dropoff.location.coordinates[1],
          lng: trip.dropoff.location.coordinates[0],
        },
      };
    }

    let eta = null;
    if (etaTarget) {
      const r = await directionsService.route([driverPos, etaTarget.coords]);
      eta = {
        toStop: etaTarget.toStop,
        seconds: r.durationSeconds,
        distanceMeters: r.distanceMeters,
        source: r.source,
      };
    }

    res.set('Cache-Control', 'no-store');
    res.json({
      driver: {
        lat: driverPos.lat,
        lng: driverPos.lng,
        updatedAt: driver.updatedAt,
      },
      eta,
    });
  } catch (err) {
    next(err);
  }
}

module.exports = {
  estimate,
  requestTrip,
  getTrip,
  unlockMatch,
  findCab,
  riderCloseTrip,
  endRideEarly,
  listMyTrips,
  getRecentDestinations,
  getMyActiveTrip,
  cancelTrip,
  getGroupFare,
  arriveTrip,
  pickUpRider,
  dropOffRider,
  getDriverLocation,
};
