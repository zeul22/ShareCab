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
const { assignDriverForTrip, assignDriverForGroup } = require('../services/dispatchService');
const { estimateSoloFare, estimateSharedFareForGroup } = require('../services/fareService');
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

async function estimate(req, res, next) {
  try {
    const data = estimateSchema.parse(req.body);
    const solo = estimateSoloFare({
      pickup: { lat: data.pickup.lat, lng: data.pickup.lng },
      dropoff: { lat: data.dropoff.lat, lng: data.dropoff.lng },
    });
    // Optimistic shared estimate: assume 2 riders, full discount.
    const shared = {
      perRider: Math.round(solo.total * (1 - 0.3) / 2),
      groupTotal: Math.round(solo.total * (1 - 0.3)),
    };
    res.json({ solo, sharedEstimate: shared });
  } catch (err) {
    next(err);
  }
}

async function requestTrip(req, res, next) {
  try {
    const data = requestSchema.parse(req.body);

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

    // Gate: shareEnabled requires an unconsumed unlock (earned by watching ads
    // or via Razorpay payment). Atomically consume one in a single round-trip
    // so two concurrent requests can't double-spend the same unlock.
    let unlock = null;
    if (data.shareEnabled) {
      const now = new Date();
      unlock = await Unlock.findOneAndUpdate(
        { rider: req.auth.userId, usedAt: null, expiresAt: { $gt: now } },
        { $set: { usedAt: now } },
        { sort: { expiresAt: 1 } },
      );
      if (!unlock) {
        throw new HttpError(
          402,
          'Matching gate not unlocked: complete 2 rewarded ads or pay to unlock',
        );
      }
    }

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
    });

    // Tag the unlock with the trip it paid for, for audit/refund flows later.
    if (unlock) {
      await Unlock.updateOne({ _id: unlock._id }, { $set: { usedForTrip: trip._id } });
    }

    // Fare estimate stored upfront for the rider's reference.
    const fare = estimateSoloFare({
      pickup: data.pickup,
      dropoff: data.dropoff,
    });
    trip.fareEstimate = fare.total;
    trip.distanceKm = fare.distanceKm;
    trip.durationMin = fare.durationMin;
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
        await assignDriverForGroup(group);
      } else {
        scheduleDeferredDispatch(trip._id);
      }
    } else {
      await assignDriverForTrip(trip);
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
        await assignDriverForGroup(group);
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
    res.json({ trip });
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
    res.json({ trip });
  } catch (err) {
    next(err);
  }
}

async function getGroupFare(req, res, next) {
  try {
    const group = await MatchGroup.findById(req.params.id).populate('trips');
    if (!group) throw new HttpError(404, 'Match group not found');
    const breakdown = estimateSharedFareForGroup(
      group.trips.map((t) => ({
        pickup: { lat: t.pickup.location.coordinates[1], lng: t.pickup.location.coordinates[0] },
        dropoff: { lat: t.dropoff.location.coordinates[1], lng: t.dropoff.location.coordinates[0] },
      })),
    );
    res.json({ group, fare: breakdown });
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
    const now = new Date();
    trip.status = 'in_progress';
    trip.startedAt = trip.startedAt || now;
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

    // Settle this rider's fare. Shared trips: per-rider share of the
    // group fare (so the discount applies even if some siblings are
    // still in-cab). Solo: the original estimate.
    let fareFinal = trip.fareEstimate;
    if (trip.matchGroup) {
      const group = await MatchGroup.findById(trip.matchGroup).populate('trips');
      if (group && group.trips.length > 0) {
        const fare = estimateSharedFareForGroup(
          group.trips.map((t) => ({
            pickup: {
              lat: t.pickup.location.coordinates[1],
              lng: t.pickup.location.coordinates[0],
            },
            dropoff: {
              lat: t.dropoff.location.coordinates[1],
              lng: t.dropoff.location.coordinates[0],
            },
          })),
        );
        fareFinal = fare.perRider;
      }
    }

    trip.status = 'completed';
    trip.completedAt = now;
    trip.fareFinal = fareFinal;
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

module.exports = {
  estimate,
  requestTrip,
  getTrip,
  listMyTrips,
  getMyActiveTrip,
  cancelTrip,
  getGroupFare,
  arriveTrip,
  pickUpRider,
  dropOffRider,
};
