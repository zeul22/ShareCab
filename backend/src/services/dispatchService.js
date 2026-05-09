const Driver = require('../models/Driver');
const Trip = require('../models/Trip');
const MatchGroup = require('../models/MatchGroup');
const env = require('../config/env');
const logger = require('../utils/logger');

/**
 * Pick the nearest available online driver for a trip or a match group, and
 * assign them. The 2dsphere index on Driver.currentLocation makes this O(log n).
 */
async function assignDriverForTrip(trip) {
  const driver = await findNearestAvailableDriver(trip.pickup.location);
  if (!driver) {
    logger.debug(`No driver available near trip ${trip._id}`);
    return null;
  }

  await Driver.updateOne(
    { _id: driver._id },
    { $set: { activeTrips: [trip._id] } },
  );

  trip.driver = driver._id;
  trip.status = 'driver_assigned';
  await trip.save();

  return driver;
}

async function assignDriverForGroup(group) {
  // A late joiner is added to a group that's already been dispatched; nothing
  // more for the dispatcher to do — the joiner's trip already inherits the driver.
  if (group.driver) return null;

  const driver = await findNearestAvailableDriver(group.centroidPickup);
  if (!driver) return null;

  const tripIds = group.trips.map((t) => t);
  await Driver.updateOne(
    { _id: driver._id },
    { $set: { activeTrips: tripIds } },
  );

  group.driver = driver._id;
  if (tripIds.length >= env.match.maxRidersPerCab) {
    group.status = 'sealed';
  }
  await group.save();

  await Trip.updateMany(
    { _id: { $in: tripIds } },
    { $set: { driver: driver._id, status: 'driver_assigned' } },
  );

  return driver;
}

async function findNearestAvailableDriver(nearPoint) {
  return Driver.findOne({
    isOnline: true,
    activeTrips: { $size: 0 },
    currentLocation: {
      $near: {
        $geometry: nearPoint,
        $maxDistance: 5000, // 5 km dispatch radius
      },
    },
  });
}

module.exports = { assignDriverForTrip, assignDriverForGroup, findNearestAvailableDriver };
