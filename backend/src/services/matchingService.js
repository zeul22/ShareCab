const Trip = require('../models/Trip');
const MatchGroup = require('../models/MatchGroup');
const env = require('../config/env');
const { distanceKm, fromGeoJSONPoint } = require('../utils/geo');
const logger = require('../utils/logger');

/**
 * ShareCab matching engine.
 *
 * Given a freshly-created Trip in `requested` status, try to find an existing
 * MatchGroup or another solo Trip whose pickup AND drop are compatible:
 *
 *   - pickup distance     <= MATCH_PICKUP_RADIUS_KM       (default 2 km)
 *   - destination distance<= MATCH_DESTINATION_RADIUS_KM  (default 4 km)
 *   - resulting group size<= MATCH_MAX_RIDERS_PER_CAB     (default 3)
 *
 * Strategy:
 *   1. Look for a forming MatchGroup whose centroid pickup is within the
 *      pickup radius and centroid drop is within the destination radius.
 *   2. If none, look for a solo `requested` trip with compatible pickup+drop
 *      and form a new MatchGroup with both trips.
 *   3. If still none, leave the trip solo and let the dispatcher pick a driver.
 *
 * For production this should run in a queue (BullMQ / Kafka) and consider
 * route shape (not just endpoints) via a routing engine. This implementation
 * uses haversine endpoints — appropriate for short-distance city rides,
 * which is exactly ShareCab's product focus.
 */
async function findMatchForTrip(tripId) {
  const trip = await Trip.findById(tripId);
  if (!trip || trip.status !== 'requested' || !trip.shareEnabled) return null;

  const tripPickup = fromGeoJSONPoint(trip.pickup.location);
  const tripDrop = fromGeoJSONPoint(trip.dropoff.location);

  // 1. Try to join an existing forming MatchGroup.
  const candidateGroups = await MatchGroup.find({
    status: 'forming',
    centroidPickup: {
      $near: {
        $geometry: trip.pickup.location,
        $maxDistance: env.match.pickupRadiusKm * 1000,
      },
    },
  }).limit(10);

  for (const group of candidateGroups) {
    if (group.trips.length >= env.match.maxRidersPerCab) continue;

    const groupDrop = fromGeoJSONPoint(group.centroidDropoff);
    if (distanceKm(tripDrop, groupDrop) > env.match.destinationRadiusKm) continue;

    return await joinGroup(group, trip);
  }

  // 2. Try to pair with another solo `requested` trip.
  const candidateTrips = await Trip.find({
    _id: { $ne: trip._id },
    status: 'requested',
    shareEnabled: true,
    matchGroup: null,
    'pickup.location': {
      $near: {
        $geometry: trip.pickup.location,
        $maxDistance: env.match.pickupRadiusKm * 1000,
      },
    },
  }).limit(10);

  for (const other of candidateTrips) {
    const otherDrop = fromGeoJSONPoint(other.dropoff.location);
    if (distanceKm(tripDrop, otherDrop) > env.match.destinationRadiusKm) continue;

    return await formGroup([other, trip]);
  }

  // 3. No match — solo dispatch path.
  logger.debug(`No match found for trip ${trip._id}; will dispatch solo.`);
  return null;
}

async function formGroup(trips) {
  const centroidPickup = centroidOf(trips.map((t) => fromGeoJSONPoint(t.pickup.location)));
  const centroidDropoff = centroidOf(trips.map((t) => fromGeoJSONPoint(t.dropoff.location)));

  const group = await MatchGroup.create({
    trips: trips.map((t) => t._id),
    status: 'forming',
    centroidPickup: { type: 'Point', coordinates: [centroidPickup.lng, centroidPickup.lat] },
    centroidDropoff: { type: 'Point', coordinates: [centroidDropoff.lng, centroidDropoff.lat] },
  });

  await Trip.updateMany(
    { _id: { $in: trips.map((t) => t._id) } },
    { $set: { matchGroup: group._id, status: 'matched' } },
  );

  logger.info(`Formed match group ${group._id} with trips ${trips.map((t) => t._id).join(', ')}`);
  return group;
}

async function joinGroup(group, trip) {
  group.trips.push(trip._id);

  const tripsInGroup = await Trip.find({ _id: { $in: group.trips } });
  const centroidPickup = centroidOf(tripsInGroup.map((t) => fromGeoJSONPoint(t.pickup.location)));
  const centroidDropoff = centroidOf(tripsInGroup.map((t) => fromGeoJSONPoint(t.dropoff.location)));

  group.centroidPickup = { type: 'Point', coordinates: [centroidPickup.lng, centroidPickup.lat] };
  group.centroidDropoff = { type: 'Point', coordinates: [centroidDropoff.lng, centroidDropoff.lat] };

  if (group.trips.length >= env.match.maxRidersPerCab) {
    group.status = 'sealed';
  }

  await group.save();

  trip.matchGroup = group._id;
  trip.status = 'matched';
  await trip.save();

  logger.info(`Trip ${trip._id} joined group ${group._id} (${group.trips.length} riders)`);
  return group;
}

function centroidOf(points) {
  const sum = points.reduce(
    (acc, p) => ({ lat: acc.lat + p.lat, lng: acc.lng + p.lng }),
    { lat: 0, lng: 0 },
  );
  return { lat: sum.lat / points.length, lng: sum.lng / points.length };
}

module.exports = { findMatchForTrip, _internals: { centroidOf } };
