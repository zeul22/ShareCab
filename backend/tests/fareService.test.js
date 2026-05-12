const fareService = require('../src/services/fareService');
const env = require('../src/config/env');

// All amounts asserted in paise. Hours/days reflected against the
// Asia/Kolkata-style local clock the surge config expects; the test
// builder helper constructs Dates with the desired local hour relative
// to the host's local timezone. We use new Date with an offset string
// so the inputs are deterministic regardless of CI host TZ.

// Returns a Date for 2026-05-XX at the given local hour:00 in Asia/Kolkata.
// We feed real UTC ISO strings + adjust for IST (+5:30) so test results
// are stable across CI hosts in different timezones.
function istDate({ day, hour }) {
  // 2026-05-04 = Mon (day=1); 2026-05-05 = Tue ... 2026-05-10 = Sun
  // We pick a base Monday (May 4 2026 IST 00:00 = May 3 2026 18:30 UTC)
  // and offset by day-of-week + hour.
  const baseUTC = Date.UTC(2026, 4, 3, 18, 30); // May 3 18:30 UTC = May 4 00:00 IST
  const ms = baseUTC + (day - 1) * 24 * 60 * 60 * 1000 + hour * 60 * 60 * 1000;
  return new Date(ms);
}

describe('classifyByCapacity', () => {
  test.each([
    [3, 'hatchback'],
    [4, 'sedan'],
    [5, 'sedan'],
    [6, 'suv'],
    [7, 'suv'],
  ])('capacity %i → %s', (cap, cls) => {
    expect(fareService.classifyByCapacity(cap)).toBe(cls);
  });

  test('null / undefined defaults to sedan (4)', () => {
    expect(fareService.classifyByCapacity(undefined)).toBe('sedan');
    expect(fareService.classifyByCapacity(null)).toBe('sedan');
  });
});

describe('surgeMultiplierFor', () => {
  // Note: getDay()/getHours() use the runtime's local timezone. Below we
  // build Dates whose UTC instant lands on the expected IST hour, but the
  // assertions check that getDay/getHours in the host's TZ produce the
  // window's day/hour. If CI runs in UTC, this still works because the
  // Date we construct corresponds to that exact UTC instant.

  test('default off-peak multiplier is 1.0', () => {
    // Build a Date whose local hour is 14 (2pm) on a Sunday, regardless
    // of test host TZ. Cheapest way: construct from an explicit local
    // time string the JS Date parser interprets in the host's TZ.
    const d = new Date(2026, 4, 10, 14, 0, 0); // Sun 14:00 local
    expect(fareService.surgeMultiplierFor(d)).toBeCloseTo(1.0, 3);
  });

  test('weekday morning peak (8-9) is 1.25', () => {
    const d = new Date(2026, 4, 11, 8, 30, 0); // Mon 08:30 local
    expect(fareService.surgeMultiplierFor(d)).toBeCloseTo(1.25, 3);
  });

  test('weekday evening peak (18-20) is 1.25', () => {
    const d = new Date(2026, 4, 11, 19, 0, 0); // Mon 19:00 local
    expect(fareService.surgeMultiplierFor(d)).toBeCloseTo(1.25, 3);
  });

  test('late night (22-05) is 1.20', () => {
    const d = new Date(2026, 4, 11, 2, 0, 0); // Mon 02:00 local
    expect(fareService.surgeMultiplierFor(d)).toBeCloseTo(1.20, 3);
  });

  test('weekend in evening-peak window does NOT surge', () => {
    const d = new Date(2026, 4, 10, 19, 0, 0); // Sun 19:00 local
    // Sun is not in weekday-evening-peak.days [1..5], so 1.0.
    expect(fareService.surgeMultiplierFor(d)).toBeCloseTo(1.0, 3);
  });
});

describe('quoteSolo', () => {
  const offPeak = new Date(2026, 4, 10, 14, 0, 0); // Sun 14:00 local — no surge

  test('sedan 5 km / 18 min has expected components in paise', () => {
    const r = fareService.quoteSolo({
      vehicleClass: 'sedan',
      distanceMeters: 5000,
      durationSeconds: 18 * 60,
      requestedAt: offPeak,
    });
    // sedan: base 3000, perMin 150, minFare 7000
    // bands: 0-3@1500/km, 3-10@1300/km, 10+@1100/km
    // distance = 3*1500 + 2*1300 = 7100
    // time = 18*150 = 2700
    // pre-surge subtotal = 3000 + 7100 + 2700 = 12800
    // no surge, no minimum floor (12800 > 7000)
    // + booking 1000 + gst 0 = 13800
    expect(r.components.base).toBe(3000);
    expect(r.components.distance).toBe(7100);
    expect(r.components.time).toBe(2700);
    expect(r.components.surgeAddition).toBe(0);
    expect(r.components.bookingFee).toBe(1000);
    expect(r.components.gst).toBe(0);
    expect(r.subtotal).toBe(12800);
    expect(r.total).toBe(13800);
    expect(r.minimumFareApplied).toBe(false);
    expect(r.surgeMultiplier).toBeCloseTo(1.0, 3);
  });

  test('hatchback is cheaper than sedan for the same trip', () => {
    const h = fareService.quoteSolo({
      vehicleClass: 'hatchback', distanceMeters: 5000, durationSeconds: 18 * 60,
      requestedAt: offPeak,
    });
    const s = fareService.quoteSolo({
      vehicleClass: 'sedan', distanceMeters: 5000, durationSeconds: 18 * 60,
      requestedAt: offPeak,
    });
    expect(h.total).toBeLessThan(s.total);
  });

  test('SUV is more expensive than sedan for the same trip', () => {
    const s = fareService.quoteSolo({
      vehicleClass: 'sedan', distanceMeters: 5000, durationSeconds: 18 * 60,
      requestedAt: offPeak,
    });
    const u = fareService.quoteSolo({
      vehicleClass: 'suv', distanceMeters: 5000, durationSeconds: 18 * 60,
      requestedAt: offPeak,
    });
    expect(u.total).toBeGreaterThan(s.total);
  });

  test('distance bands kick in at 3km and 10km boundaries', () => {
    // sedan band 0-3 @ 1500/km, 3-10 @ 1300/km, 10+ @ 1100/km
    const at3km = fareService.quoteSolo({
      vehicleClass: 'sedan', distanceMeters: 3000, durationSeconds: 600,
      requestedAt: offPeak,
    });
    // distance at 3km = 3 * 1500 = 4500
    expect(at3km.components.distance).toBe(4500);

    const at10km = fareService.quoteSolo({
      vehicleClass: 'sedan', distanceMeters: 10000, durationSeconds: 600,
      requestedAt: offPeak,
    });
    // 3*1500 + 7*1300 = 4500 + 9100 = 13600
    expect(at10km.components.distance).toBe(13600);

    const at15km = fareService.quoteSolo({
      vehicleClass: 'sedan', distanceMeters: 15000, durationSeconds: 600,
      requestedAt: offPeak,
    });
    // 3*1500 + 7*1300 + 5*1100 = 4500 + 9100 + 5500 = 19100
    expect(at15km.components.distance).toBe(19100);
  });

  test('minimum fare floor on very short trip', () => {
    const r = fareService.quoteSolo({
      vehicleClass: 'sedan',
      distanceMeters: 500,    // 0.5 km
      durationSeconds: 3 * 60,
      requestedAt: offPeak,
    });
    // pre-floor sedan: 3000 base + 0.5*1500 dist + 3*150 time = 3000 + 750 + 450 = 4200
    // floor = 7000 → subtotal = 7000
    // + booking 1000 + gst 0 = 8000
    expect(r.minimumFareApplied).toBe(true);
    expect(r.subtotal).toBe(7000);
    expect(r.total).toBe(8000);
  });

  test('surge addition computed on pre-booking subtotal', () => {
    const peak = new Date(2026, 4, 11, 8, 30, 0); // Mon 08:30 = 1.25x
    const r = fareService.quoteSolo({
      vehicleClass: 'sedan',
      distanceMeters: 5000,
      durationSeconds: 18 * 60,
      requestedAt: peak,
    });
    // base 3000 + dist 7100 + time 2700 = 12800
    // surge addition = 12800 * 0.25 = 3200
    expect(r.components.surgeAddition).toBe(3200);
    expect(r.subtotal).toBe(16000);
    expect(r.total).toBe(17000); // + booking 1000
  });
});

describe('quoteShared — proportional allocation', () => {
  const offPeak = new Date(2026, 4, 10, 14, 0, 0); // Sun 14:00 local

  test('two riders with different leg lengths pay different amounts', () => {
    const r = fareService.quoteShared({
      vehicleClass: 'sedan',
      members: [
        { tripId: 'short', distanceMeters: 2000, durationSeconds: 8 * 60 },
        { tripId: 'long',  distanceMeters: 6000, durationSeconds: 22 * 60 },
      ],
      requestedAt: offPeak,
    });
    const shortRider = r.allocations.find((a) => a.tripId === 'short');
    const longRider = r.allocations.find((a) => a.tripId === 'long');
    // Long-leg rider pays strictly more than short-leg rider.
    expect(longRider.total).toBeGreaterThan(shortRider.total);
  });

  test('long-leg rider in a shared trip saves vs solo', () => {
    const longSolo = fareService.quoteSolo({
      vehicleClass: 'sedan',
      distanceMeters: 6000,
      durationSeconds: 22 * 60,
      requestedAt: offPeak,
    });
    const shared = fareService.quoteShared({
      vehicleClass: 'sedan',
      members: [
        { tripId: 'short', distanceMeters: 2000, durationSeconds: 8 * 60 },
        { tripId: 'long',  distanceMeters: 6000, durationSeconds: 22 * 60 },
      ],
      requestedAt: offPeak,
    });
    const longShared = shared.allocations.find((a) => a.tripId === 'long');
    expect(longShared.total).toBeLessThan(longSolo.total);
  });

  test('short-leg rider may hit minimum fare floor', () => {
    const shared = fareService.quoteShared({
      vehicleClass: 'sedan',
      members: [
        { tripId: 'tiny', distanceMeters: 500, durationSeconds: 2 * 60 },
        { tripId: 'long', distanceMeters: 8000, durationSeconds: 25 * 60 },
      ],
      requestedAt: offPeak,
    });
    const tiny = shared.allocations.find((a) => a.tripId === 'tiny');
    // Floor at sedan minFare 7000 → with booking ≥ 8000
    expect(tiny.total).toBeGreaterThanOrEqual(8000);
  });

  test('three-rider group totals match sum of allocations', () => {
    const shared = fareService.quoteShared({
      vehicleClass: 'sedan',
      members: [
        { tripId: 'a', distanceMeters: 3000, durationSeconds: 12 * 60 },
        { tripId: 'b', distanceMeters: 5000, durationSeconds: 18 * 60 },
        { tripId: 'c', distanceMeters: 7000, durationSeconds: 25 * 60 },
      ],
      requestedAt: offPeak,
    });
    const sum = shared.allocations.reduce((a, x) => a + x.total, 0);
    expect(sum).toBe(shared.groupTotal);
  });
});

describe('GST line item', () => {
  const offPeak = new Date(2026, 4, 10, 14, 0, 0);

  // We toggle env.fare.gst.enabled in the tests; restore after.
  const origEnabled = env.fare.gst.enabled;
  afterAll(() => { env.fare.gst.enabled = origEnabled; });

  test('zero by default (no GSTIN yet)', () => {
    env.fare.gst.enabled = false;
    const r = fareService.quoteSolo({
      vehicleClass: 'sedan', distanceMeters: 5000, durationSeconds: 18 * 60,
      requestedAt: offPeak,
    });
    expect(r.components.gst).toBe(0);
    expect(r.driverPayout).toBe(r.total);
  });

  test('5% of (subtotal + booking) when enabled', () => {
    env.fare.gst.enabled = true;
    const r = fareService.quoteSolo({
      vehicleClass: 'sedan', distanceMeters: 5000, durationSeconds: 18 * 60,
      requestedAt: offPeak,
    });
    // subtotal 12800 + booking 1000 = 13800
    // GST 5% = 690
    expect(r.components.gst).toBe(690);
    expect(r.total).toBe(12800 + 1000 + 690);
    expect(r.driverPayout).toBe(r.total - 690);
  });
});

describe('legacy shim — estimateSoloFare returns paise', () => {
  test('signature preserved but total is paise (was rupees)', () => {
    const r = fareService.estimateSoloFare({
      pickup: { lat: 12.9716, lng: 77.5946 },
      dropoff: { lat: 12.9352, lng: 77.6245 }, // ~5 km away in BLR
    });
    expect(r.total).toBeGreaterThan(5000);   // > ₹50
    expect(r.total).toBeLessThan(30000);     // < ₹300
    expect(r.breakdown).toBeDefined();
    expect(r.breakdown.components).toBeDefined();
  });
});
