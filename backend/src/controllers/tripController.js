const { z } = require('zod');
const Trip = require('../models/Trip');
const MatchGroup = require('../models/MatchGroup');
const { HttpError } = require('../middleware/errorHandler');
const { findMatchForTrip } = require('../services/matchingService');
const { assignDriverForTrip, assignDriverForGroup } = require('../services/dispatchService');
const { estimateSoloFare, estimateSharedFareForGroup } = require('../services/fareService');
const { broadcastTripUpdate } = require('../services/notificationService');

const point = z.object({
  address: z.string().optional(),
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
});

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

    // Fare estimate stored upfront for the rider's reference.
    const fare = estimateSoloFare({
      pickup: data.pickup,
      dropoff: data.dropoff,
    });
    trip.fareEstimate = fare.total;
    trip.distanceKm = fare.distanceKm;
    trip.durationMin = fare.durationMin;
    await trip.save();

    // Try to match into / form a group, then dispatch a driver.
    const group = data.shareEnabled ? await findMatchForTrip(trip._id) : null;

    if (group) {
      await assignDriverForGroup(group);
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

module.exports = { estimate, requestTrip, getTrip, listMyTrips, cancelTrip, getGroupFare };
