function num(value, fallback) {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
}

const env = {
  port: num(process.env.PORT, 4000),
  nodeEnv: process.env.NODE_ENV || 'development',

  jwtSecret: process.env.JWT_SECRET || 'dev-only-insecure-secret',
  jwtExpiresIn: process.env.JWT_EXPIRES_IN || '7d',

  match: {
    destinationRadiusKm: num(process.env.MATCH_DESTINATION_RADIUS_KM, 4),
    pickupRadiusKm: num(process.env.MATCH_PICKUP_RADIUS_KM, 2),
    maxDetourKm: num(process.env.MATCH_MAX_DETOUR_KM, 2),
    maxRidersPerCab: num(process.env.MATCH_MAX_RIDERS_PER_CAB, 3),
  },

  fare: {
    base: num(process.env.FARE_BASE, 30),
    perKm: num(process.env.FARE_PER_KM, 12),
    perMin: num(process.env.FARE_PER_MIN, 1),
    shareDiscount: num(process.env.FARE_SHARE_DISCOUNT, 0.3),
  },
};

module.exports = env;
