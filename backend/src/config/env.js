function num(value, fallback) {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
}

const env = {
  port: num(process.env.PORT, 4000),
  nodeEnv: process.env.NODE_ENV || 'development',

  // Defaults to the Mongo service from the repo's docker-compose.yml so a fresh
  // `npm run dev` works after `docker compose up -d`. Override via env for
  // staging / prod or to point at MongoDB Atlas.
  mongoUri: process.env.MONGODB_URI || 'mongodb://localhost:27017/sharecab',

  jwtSecret: process.env.JWT_SECRET || 'dev-only-insecure-secret',
  jwtExpiresIn: process.env.JWT_EXPIRES_IN || '7d',

  match: {
    destinationRadiusKm: num(process.env.MATCH_DESTINATION_RADIUS_KM, 4),
    pickupRadiusKm: num(process.env.MATCH_PICKUP_RADIUS_KM, 2),
    maxDetourKm: num(process.env.MATCH_MAX_DETOUR_KM, 2),
    maxRidersPerCab: num(process.env.MATCH_MAX_RIDERS_PER_CAB, 3),
    // Window during which a `shareEnabled=true` trip with no immediate match
    // waits before falling back to solo dispatch. Lets a co-rider arriving
    // moments later actually pair instead of finding the first rider already
    // committed to a driver. 8s is a reasonable demo default.
    dispatchDelayMs: num(process.env.MATCH_DISPATCH_DELAY_MS, 8000),
  },

  fare: {
    base: num(process.env.FARE_BASE, 30),
    perKm: num(process.env.FARE_PER_KM, 12),
    perMin: num(process.env.FARE_PER_MIN, 1),
    shareDiscount: num(process.env.FARE_SHARE_DISCOUNT, 0.3),
  },

  unlock: {
    // How long an unlock is valid after creation, before it must be used.
    ttlSeconds: num(process.env.UNLOCK_TTL_SECONDS, 60 * 60), // 1 hour
    // Number of rewarded ads the rider must complete to earn one unlock.
    adsPerUnlock: num(process.env.UNLOCK_ADS_PER_UNLOCK, 2),
    // Price for the paid path, in paise. Final number TBD with the team.
    pricePaise: num(process.env.UNLOCK_PRICE_PAISE, 1900), // ₹19.00 placeholder
  },
};

module.exports = env;
