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

  driver.activeTrip = trip._id;
  await driver.save();

  trip.driver = driver._id;
  trip.status = 'driver_assigned';
  await trip.save();

  return driver;
}

async function assignDriverForGroup(group) {
  const driver = await findNearestAvailableDriver(group.centroidPickup);
  if (!driver) return null;

  driver.activeTrip = group.trips[0];
  await driver.save();

  group.driver = driver._id;
  group.status = 'sealed';
  await group.save();

  await Trip.updateMany(
    { _id: { $in: group.trips } },
    { $set: { driver: driver._id, status: 'driver_assigned' } },
  );

  return driver;
}

async function findNearestAvailableDriver(nearPoint) {
  return Driver.findOne({
    isOnline: true,
    activeTrip: null,
    currentLocation: {
      $near: {
        $geometry: nearPoint,
        $maxDistance: 5000, // 5 km dispatch radius
      },
    },
  });
}

module.exports = { assignDriverForTrip, assignDriverForGroup, findNearestAvailableDriver };

// eslint-disable-next-line no-unused-vars
const _maxDetour = env.match.maxDetourKm; // referenced for future routing-aware dispatch
