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

  // Google Maps Platform key for the server-side Directions API call in
  // fareService. Separate from the client-side keys configured in
  // app/ios + driver/ios + Android manifests — those are restricted by
  // bundle id / SHA-1. The server-side key must allow Directions API
  // and is restricted by HTTP referer (or unrestricted, the Cloud Run
  // egress IP rotates). When empty, fareService falls back to a
  // haversine + fallback-speed estimate.
  googleMapsKey: process.env.GOOGLE_MAPS_KEY || '',

  // =============================================================================
  // Fare config
  //
  // ALL amounts in paise. Rupees on the wire was the V1 footgun — Razorpay's
  // amount field is paise too, so unifying here avoids ×100 acrobatics
  // throughout. Per-class rates / surge windows / distance bands are
  // pricing-strategy decisions and live in code (this file). Operational
  // knobs that move with market conditions (booking fee, GST toggle, share
  // discount, global surge multiplier) are env-overridable.
  // =============================================================================
  fare: {
    // Three vehicle classes derived from Driver.vehicle.capacity:
    //   capacity ≥ 6  → 'suv'
    //   capacity ≥ 4  → 'sedan'
    //   otherwise     → 'hatchback'
    // Each class has a base fare, a per-minute time charge, a minimum
    // fare floor, and distance bands (regressive per-km — short rides
    // cost more per km, long rides cheaper). Picking these is more
    // judgment than science; benchmarked against Uber Go / Premier / XL
    // India pricing as of late 2025 and rounded for legibility.
    vehicleClasses: {
      hatchback: {
        base: 2500,       // ₹25.00
        perMin: 100,      // ₹1.00 per min
        minFare: 5000,    // ₹50.00 floor
        distanceBands: [
          { upToKm: 3,  perKm: 1200 },   // ₹12.00 / km for the first 3 km
          { upToKm: 10, perKm: 1000 },   // ₹10.00 / km from 3-10 km
          { perKm: 900 },                // ₹ 9.00 / km beyond 10 km
        ],
      },
      sedan: {
        base: 3000,       // ₹30.00
        perMin: 150,      // ₹1.50 per min
        minFare: 7000,    // ₹70.00 floor
        distanceBands: [
          { upToKm: 3,  perKm: 1500 },   // ₹15.00 / km for the first 3 km
          { upToKm: 10, perKm: 1300 },
          { perKm: 1100 },
        ],
      },
      suv: {
        base: 4000,       // ₹40.00
        perMin: 200,      // ₹2.00 per min
        minFare: 10000,   // ₹100.00 floor
        distanceBands: [
          { upToKm: 3,  perKm: 2000 },
          { upToKm: 10, perKm: 1700 },
          { perKm: 1500 },
        ],
      },
    },

    // Time-of-day surge. Hour of day in local 24h (Asia/Kolkata, see
    // `env.timezone` if we later differentiate). Days: 0=Sunday … 6=Saturday.
    // First matching window wins; everything else is `default` (1.0x).
    // Picked conservatively — Uber/Ola hit 1.5x-2.5x routinely; we keep our
    // brand promise of affordable shared rides intact at 1.25x.
    surge: {
      windows: [
        { name: 'weekday-morning-peak',
          days: [1, 2, 3, 4, 5], hours: [8, 9],
          mult: 1.25 },
        { name: 'weekday-evening-peak',
          days: [1, 2, 3, 4, 5], hours: [18, 19, 20],
          mult: 1.25 },
        { name: 'late-night',
          days: [0, 1, 2, 3, 4, 5, 6], hours: [22, 23, 0, 1, 2, 3, 4, 5],
          mult: 1.20 },
      ],
      // Operational multiplier on top of the time-window result. Set to
      // 1.5 during a city-wide event without re-deploying. 1.0 = no
      // change. We don't expose values > 2.0 — that's irresponsible
      // pricing in India where ₹500 trips become ₹1000.
      globalMultiplier: num(process.env.FARE_SURGE_GLOBAL_MULTIPLIER, 1.0),
      default: 1.0,
    },

    // Flat platform charge per trip, on top of per-km/per-min.
    // ₹10 lands inside the typical Uber India "booking fee" range (₹5-25)
    // without being grabby on small fares.
    bookingFeePaise: num(process.env.FARE_BOOKING_FEE_PAISE, 1000),

    // Share discount: applied to the SUM of solo fares for matched riders
    // before allocation. 0.3 = 30% off the combined solo fare — the rest
    // is allocated proportional to each rider's solo distance.
    shareDiscount: num(process.env.FARE_SHARE_DISCOUNT, 0.30),

    // GST on rider-side fares. India's section 9(5) places the tax
    // liability on the platform (us) at 5% under the composition scheme.
    // We MUST hold a GSTIN before charging this — until then `enabled` is
    // false and the line item shows ₹0 in the breakdown. Flip via env.
    gst: {
      enabled: (process.env.FARE_GST_ENABLED || '').toLowerCase() === 'true',
      ratePct: num(process.env.FARE_GST_PCT, 5),
    },

    // Average speed (km/h) used when the Directions API is unavailable or
    // unconfigured. Calibrated for tier-1 Indian city traffic; ops can dial
    // up for tier-2 cities with less congestion.
    fallbackSpeedKmph: num(process.env.FARE_FALLBACK_SPEED_KMPH, 22),
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

  // =============================================================================
  // Driver dispatch (the Uber-style offer flow)
  // =============================================================================
  dispatch: {
    // How long a driver has to accept/reject an offered trip before we
    // auto-reject and re-dispatch. 30s gives a driver who's mid-task
    // (eating, refueling, glancing at the phone) realistic time to react;
    // shorter windows feel punitive and ramp the re-dispatch churn. The
    // findNearestAvailableDriver query is anchored on the rider's pickup
    // location, so the nearest online driver is always the one being
    // offered to — closer drivers get first dibs.
    offerTimeoutMs: num(process.env.DISPATCH_OFFER_TIMEOUT_MS, 30_000),
    // Max distance (metres) the matching engine looks when finding a
    // driver. Mirrors what `findNearestAvailableDriver` historically
    // hardcoded; lifted to env so we can tune per market.
    radiusMeters: num(process.env.DISPATCH_RADIUS_METERS, 5000),
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
