const env = require('../config/env');
const { distanceKm } = require('../utils/geo');

/**
 * Estimate the fare for a single trip.
 *
 * Solo fare = base + (perKm * km) + (perMin * estimatedMin)
 * Shared fare = solo fare * (1 - shareDiscount), then split across riders in the group.
 */
function estimateSoloFare({ pickup, dropoff, averageSpeedKmph = 25 }) {
  const km = distanceKm(pickup, dropoff);
  const minutes = (km / averageSpeedKmph) * 60;
  const total = env.fare.base + env.fare.perKm * km + env.fare.perMin * minutes;
  return { total: round(total), distanceKm: round(km, 2), durationMin: round(minutes, 0) };
}

function estimateSharedFareForGroup(trips) {
  // Approximate group route as the bounding two extreme points (rough but sufficient for an estimate).
  // A real implementation would integrate with a routing engine (OSRM, Google Directions, etc.).
  const allPoints = trips.flatMap((t) => [t.pickup, t.dropoff]);
  const totalKm = approximateRouteKm(allPoints);
  const minutes = (totalKm / 25) * 60;
  const grossSolo = env.fare.base + env.fare.perKm * totalKm + env.fare.perMin * minutes;
  const discounted = grossSolo * (1 - env.fare.shareDiscount);
  const perRider = discounted / trips.length;
  return {
    perRider: round(perRider),
    groupTotal: round(discounted),
    distanceKm: round(totalKm, 2),
    durationMin: round(minutes, 0),
  };
}

function approximateRouteKm(points) {
  let total = 0;
  for (let i = 1; i < points.length; i += 1) {
    total += distanceKm(points[i - 1], points[i]);
  }
  return total;
}

function round(n, decimals = 0) {
  const f = 10 ** decimals;
  return Math.round(n * f) / f;
}

module.exports = { estimateSoloFare, estimateSharedFareForGroup };
