const { z } = require('zod');
const Trip = require('../models/Trip');
const Driver = require('../models/Driver');
const MatchGroup = require('../models/MatchGroup');
const User = require('../models/User');
const Unlock = require('../models/Unlock');
const env = require('../config/env');
const logger = require('../utils/logger');
const { isWithinIndia } = require('../utils/geo');
const { HttpError } = require('../middleware/errorHandler');
const { findMatchForTrip } = require('../services/matchingService');
const { assignDriverForTrip, assignDriverForGroup } = require('../services/dispatchService');
const { estimateSoloFare, estimateSharedFareForGroup } = require('../services/fareService');
const { broadcastTripUpdate } = require('../services/notificationService');

const point = z
  .object({
    address: z.string().optional(),
    lat: z.number().min(-90).max(90),
    lng: z.number().min(-180).max(180),
  })
  .refine(isWithinIndia, { message: 'Coordinates must be within India' });

const requestSchema = z.object({
  pickup: point,
  dropoff: point,
  shareEnabled: z.boolean().default(true),
});

const estimateSchema = z.object({
  pickup: point,
  dropoff: point,
});

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

    const refreshed = await Trip.findById(trip._id).populate('matchGroup driver');
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
      } else {
        await assignDriverForTrip(trip);
      }

      const refreshed = await Trip.findById(tripId).populate('matchGroup driver');
      await broadcastTripUpdate(refreshed);
    } catch (err) {
      logger.error(`Deferred dispatch failed for trip ${tripId}: ${err.message}`);
    }
  }, env.match.dispatchDelayMs);
}

async function getTrip(req, res, next) {
  try {
    const trip = await Trip.findById(req.params.id).populate('matchGroup driver');
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

    if (trip.matchGroup) {
      const group = await MatchGroup.findById(trip.matchGroup);
      if (group) {
        group.trips = group.trips.filter((t) => t.toString() !== trip._id.toString());
        if (group.trips.length === 0) group.status = 'cancelled';
        await group.save();
      }
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

async function startTrip(req, res, next) {
  try {
    const { trip } = await loadDriverTrip(req);
    if (trip.status !== 'arriving') {
      throw new HttpError(400, `Cannot start from status ${trip.status}`);
    }
    const filter = tripScopeFilter(trip);
    await Trip.updateMany(filter, { $set: { status: 'in_progress', startedAt: new Date() } });
    if (trip.matchGroup) {
      await MatchGroup.findByIdAndUpdate(trip.matchGroup, { $set: { status: 'in_progress' } });
    }
    const trips = await Trip.find(filter).populate('driver matchGroup');
    res.json({ trips });
  } catch (err) {
    next(err);
  }
}

async function completeTrip(req, res, next) {
  try {
    const { driver, trip } = await loadDriverTrip(req);
    if (trip.status !== 'in_progress') {
      throw new HttpError(400, `Cannot complete from status ${trip.status}`);
    }
    const now = new Date();

    let riderIds;
    if (trip.matchGroup) {
      const group = await MatchGroup.findById(trip.matchGroup).populate('trips');
      const fare = estimateSharedFareForGroup(
        group.trips.map((t) => ({
          pickup: { lat: t.pickup.location.coordinates[1], lng: t.pickup.location.coordinates[0] },
          dropoff: { lat: t.dropoff.location.coordinates[1], lng: t.dropoff.location.coordinates[0] },
        })),
      );
      riderIds = group.trips.map((t) => t.rider);
      await Trip.updateMany(
        { matchGroup: trip.matchGroup },
        { $set: { status: 'completed', completedAt: now, fareFinal: fare.perRider } },
      );
      group.status = 'completed';
      await group.save();
    } else {
      riderIds = [trip.rider];
      await Trip.updateOne(
        { _id: trip._id },
        { $set: { status: 'completed', completedAt: now, fareFinal: trip.fareEstimate } },
      );
    }

    // Bump ride counters: each rider gets +1, the driver's user gets +1 (one drive).
    await User.updateMany({ _id: { $in: riderIds } }, { $inc: { totalRides: 1 } });
    await User.updateOne({ _id: driver.user }, { $inc: { totalRides: 1 } });

    await Driver.updateOne(
      { _id: driver._id },
      { $set: { activeTrips: [] } },
    );

    const trips = await Trip.find(tripScopeFilter(trip)).populate('driver matchGroup');
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
  cancelTrip,
  getGroupFare,
  arriveTrip,
  startTrip,
  completeTrip,
};
