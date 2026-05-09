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
    // Window during which a `shareEnabled=true` trip waits for a co-rider.
    // After this expires the trip stays in `requested` state — we no longer
    // auto-fall-back to solo dispatch; the rider explicitly decides what
    // to do next from the empty-state UI on the searching screen.
    dispatchDelayMs: num(process.env.MATCH_DISPATCH_DELAY_MS, 5 * 60 * 1000),
  },

  fare: {
    base: num(process.env.FARE_BASE, 30),
    perKm: num(process.env.FARE_PER_KM, 12),
    perMin: num(process.env.FARE_PER_MIN, 1),
    shareDiscount: num(process.env.FARE_SHARE_DISCOUNT, 0.3),
  },

  unlock: {
    // How long a paid unlock is valid after creation. 30 min is enough for
    // one search journey (pick locations → ads/payment → wait for match
    // → confirm) without letting riders sit on a paid pass for hours.
    ttlSeconds: num(process.env.UNLOCK_TTL_SECONDS, 30 * 60), // 30 min
    // Default number of rewarded ads the rider must complete to earn one
    // unlock. Overridden per-rider by rating tiers in
    // unlockController.adsRequiredForRating — high-rated riders get
    // through faster, low-rated ones face more friction.
    adsPerUnlock: num(process.env.UNLOCK_ADS_PER_UNLOCK, 2),
    // Price for the paid path, in paise. ₹50 ≈ 10% friction on a typical
    // ₹500 shared-fare saving — small enough to be a casual one-tap, big
    // enough to filter low-intent users.
    pricePaise: num(process.env.UNLOCK_PRICE_PAISE, 5000), // ₹50.00
  },
};

module.exports = env;
