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
    // Rider-only mode. When TRUE we skip driver dispatch entirely — the
    // matching engine still pairs riders, but they're expected to
    // coordinate their own cab via chat. The unlock gate also moves from
    // trip-creation to match-reveal time (rider pays / watches ads only
    // after a match is found, not before). Used while we're bootstrapping
    // supply before drivers join. Flip back to false once drivers are on.
    riderOnly: (process.env.MATCH_RIDER_ONLY || '').toLowerCase() === 'true',
  },

  fare: {
    base: num(process.env.FARE_BASE, 30),
    perKm: num(process.env.FARE_PER_KM, 12),
    perMin: num(process.env.FARE_PER_MIN, 1),
    shareDiscount: num(process.env.FARE_SHARE_DISCOUNT, 0.3),
  },

  trip: {
    // Distance sanity rails on every trip request. Pickup→drop straight
    // line below `minDistanceKm` is nearly always a misclick or a same-
    // address pair; above `maxDistanceKm` is intercity (not what
    // ShareCab is for). Values are in kilometres.
    minDistanceKm: num(process.env.TRIP_MIN_DISTANCE_KM, 0.3),
    maxDistanceKm: num(process.env.TRIP_MAX_DISTANCE_KM, 100),
  },

  msg91: {
    // Server-side authkey used by the backend to validate access tokens
    // minted by the MSG91 Flutter widget. NEVER ship this in the app.
    // Empty string makes /auth/otp/msg91/verify return 503.
    authKey: process.env.MSG91_AUTH_KEY || '',
    // Public widget credentials used by the Flutter SDK. These are
    // client-side values by design, and may be served to the app through
    // /api/auth/otp/msg91/config. Do not put MSG91_AUTH_KEY here.
    widgetId: process.env.MSG91_WIDGET_ID || '',
    widgetAuthToken:
      process.env.MSG91_WIDGET_AUTH_TOKEN ||
      process.env.MSG91_AUTH_TOKEN ||
      process.env.MSG91_TOKEN_AUTH ||
      '',
    // Explicit opt-in for the dev OTP (`123456`) while DLT registration
    // or widget setup is pending. When TRUE, /auth/otp/{request,verify}
    // run the local-only path. Production must NEVER set this — turning
    // it on lets anyone log in as any phone with the hardcoded code.
    devFallback: (process.env.MSG91_DEV_FALLBACK || '').toLowerCase() === 'true',
    // Override only for tests. The real prod URL is the default.
    verifyUrl:
      process.env.MSG91_VERIFY_URL ||
      'https://control.msg91.com/api/v5/widget/verifyAccessToken',
  },

  razorpay: {
    // Test-mode keys are fine for local dev; switch to live keys in prod.
    // If keyId/keySecret are missing, the platform falls back to STUB mode
    // (orders are fake-created, signatures aren't verified) so the demo
    // keeps working without real credentials.
    keyId: process.env.RAZORPAY_KEY_ID || '',
    keySecret: process.env.RAZORPAY_KEY_SECRET || '',
    // Webhook secret is the separate one configured in Razorpay dashboard
    // for server-to-server callbacks. Used by the webhook HMAC verifier.
    webhookSecret: process.env.RAZORPAY_WEBHOOK_SECRET || '',
  },

  driverSub: {
    // Monthly driver subscription. Drivers without an active sub are
    // blocked at /api/drivers/online. Pricing TBD — ₹199/month is roughly
    // 1% of a typical tier-1 driver's monthly revenue (meaningful but not
    // punitive). Configurable so ops can A/B different tiers.
    pricePaise: num(process.env.DRIVER_SUBSCRIPTION_PRICE_PAISE, 19900), // ₹199
    daysPerCycle: num(process.env.DRIVER_SUBSCRIPTION_DAYS, 30),
    // First-month-free at signup to seed driver supply during launch.
    // Set to 0 to disable.
    freeTrialDays: num(process.env.DRIVER_FREE_TRIAL_DAYS, 30),
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
