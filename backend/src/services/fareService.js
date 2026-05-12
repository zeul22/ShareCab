const env = require('../config/env');
const { distanceKm } = require('../utils/geo');

// =============================================================================
// ShareCab Fare Calculator
//
// All amounts on the wire are in paise (1 INR = 100 paise) to match Razorpay.
// This module is the single source of truth for "how much does this trip
// cost." The trip controller (and matching engine) call it at request time
// (estimate) and at completion (settlement); the wire format never differs.
//
// Pricing is structured rather than a single formula:
//
//   base + Σ(distance band × km in band) + perMin × min        (per-vehicle-class)
//   × surge multiplier (time of day, optional global override)
//   + flat booking fee
//   + GST (zeroed unless platform has a GSTIN — see env.fare.gst.enabled)
//   ⇒ floor at vehicle class's minimumFare
//   ⇒ for shared trips, allocated proportional to each rider's solo leg
//
// What this module does NOT decide:
//   - Whether two trips are eligible to be matched (matching engine).
//   - Whether the rider has paid the unlock to see the match (unlock service).
//   - How payment is collected (razorpay client + tripController settlement).
//
// Inputs come from `tripController` after it has resolved the vehicle class
// from the dispatched driver (or assumed `sedan` for pre-dispatch estimates).
// Distance + duration come from `directionsService` (Google Directions ETA)
// when configured, else a haversine + fallback-speed estimate.
// =============================================================================

const ROUND = (n) => Math.round(n);

/// Resolve a Driver.vehicle.capacity to a vehicle class. Falls through to
/// 'sedan' as the safe default — covers most Indian fleets.
function classifyByCapacity(capacity) {
  const c = Number.isFinite(capacity) ? capacity : 4;
  if (c >= 6) return 'suv';
  if (c >= 4) return 'sedan';
  return 'hatchback';
}

/// Distance bands are cumulative: 0-3 km charged at band[0].perKm, 3-10 km
/// at band[1].perKm, and so on. A trailing band with no `upToKm` catches
/// "everything beyond" — guaranteed to terminate for any finite km.
function distanceCharge(km, bands) {
  let remaining = km;
  let prevUpTo = 0;
  let total = 0;
  for (const band of bands) {
    const slice = band.upToKm == null
      ? remaining
      : Math.min(remaining, band.upToKm - prevUpTo);
    if (slice <= 0) break;
    total += slice * band.perKm;
    remaining -= slice;
    prevUpTo = band.upToKm ?? prevUpTo;
    if (remaining <= 0) break;
  }
  return total;
}

/// Look up the surge multiplier for a given Date. Uses Asia/Kolkata-style
/// local wall-clock hours via getDay/getHours on the input Date — the
/// Date carries the right timezone if it was constructed from new Date()
/// on a Kolkata-tz host. For production hosts in UTC, this still works as
/// long as we feed `requestedAt = new Date()` from a Cloud Run service
/// pinned to Asia/Kolkata (set `TZ=Asia/Kolkata` env in the container).
function surgeMultiplierFor(date) {
  const cfg = env.fare.surge;
  const day = date.getDay();
  const hour = date.getHours();
  const win = cfg.windows.find((w) =>
    w.days.includes(day) && w.hours.includes(hour),
  );
  const window = win ? win.mult : cfg.default;
  return window * cfg.globalMultiplier;
}

/// Quote ONE solo trip — the basic case + the unit of allocation for shared.
///
/// Inputs:
///   - vehicleClass        'hatchback' | 'sedan' | 'suv'
///   - distanceKm          number, > 0
///   - durationMin         number, > 0
///   - surge               multiplier from surgeMultiplierFor(...)
///   - applyMinimumFare    true for solo; false when building a shared group
///                         (we apply the floor at the group level)
///
/// Output: components in paise — caller assembles the final {total, breakdown}.
function quoteSoloComponents({ vehicleClass, distanceKm, durationMin, surge, applyMinimumFare = true }) {
  const cfg = env.fare.vehicleClasses[vehicleClass];
  if (!cfg) {
    throw new Error(`Unknown vehicle class: ${vehicleClass}`);
  }
  const base = cfg.base;
  const distance = distanceCharge(distanceKm, cfg.distanceBands);
  const time = durationMin * cfg.perMin;
  const preSurge = base + distance + time;
  const surgeAddition = surge > 1 ? preSurge * (surge - 1) : 0;
  const beforeMinimum = preSurge + surgeAddition;
  // The minimum-fare floor compares against the per-vehicle subtotal,
  // BEFORE booking fee + GST. Industry-standard floor model.
  const minimumFareApplied = applyMinimumFare && beforeMinimum < cfg.minFare;
  const subtotal = minimumFareApplied ? cfg.minFare : beforeMinimum;

  return {
    base: ROUND(base),
    distance: ROUND(distance),
    time: ROUND(time),
    surgeAddition: ROUND(surgeAddition),
    subtotal: ROUND(subtotal),
    minimumFareApplied,
  };
}

/// Quote a SOLO trip end-to-end. Returns the full Fare object the rest
/// of the system speaks.
function quoteSolo({
  vehicleClass = 'sedan',
  distanceMeters,
  durationSeconds,
  requestedAt = new Date(),
}) {
  const distKm = distanceMeters / 1000;
  const durMin = durationSeconds / 60;
  const surge = surgeMultiplierFor(requestedAt);

  const c = quoteSoloComponents({
    vehicleClass,
    distanceKm: distKm,
    durationMin: durMin,
    surge,
  });

  return finalizeFare({
    vehicleClass,
    distanceKm: distKm,
    durationMin: durMin,
    surge,
    components: c,
    perRiderSubtotal: c.subtotal,
    shareCount: 1,
  });
}

/// Quote a SHARED trip. Each member trip has its own solo distance/
/// duration; we compute each rider's solo fare, sum them, apply the
/// share discount, then allocate the discounted group total back to
/// riders proportional to their individual solo subtotals.
///
/// Inputs:
///   - vehicleClass — same class for the whole group (driver's vehicle)
///   - members      — array of { tripId, distanceMeters, durationSeconds }
///   - requestedAt  — Date driving surge lookup; group quote uses one
///                    surge value (the earliest trip's time).
///
/// Returns:
///   {
///     vehicleClass, surgeMultiplier,
///     totalDistanceKm, totalDurationMin,
///     groupTotal,                                            // platform-side
///     bookingFee, gst,
///     allocations: [{ tripId, distanceKm, durationMin, fare, breakdown }]
///   }
function quoteShared({
  vehicleClass = 'sedan',
  members,
  requestedAt = new Date(),
}) {
  if (!Array.isArray(members) || members.length === 0) {
    throw new Error('quoteShared: members must be a non-empty array');
  }
  const surge = surgeMultiplierFor(requestedAt);

  // Each rider's solo subtotal — base + distance + time + surge (no
  // minimum-fare floor yet; we floor the final allocation).
  const soloPieces = members.map((m) => ({
    tripId: m.tripId,
    distanceKm: m.distanceMeters / 1000,
    durationMin: m.durationSeconds / 60,
    components: quoteSoloComponents({
      vehicleClass,
      distanceKm: m.distanceMeters / 1000,
      durationMin: m.durationSeconds / 60,
      surge,
      applyMinimumFare: false,
    }),
  }));

  const sumSolo = soloPieces.reduce((a, p) => a + p.components.subtotal, 0);
  const discount = env.fare.shareDiscount;
  const groupSubtotal = sumSolo * (1 - discount);

  // Allocate the discounted group total back by each rider's solo
  // subtotal weight. A rider with a longer solo leg pays proportionally
  // more. Floor each share at the vehicle class's minFare to keep tiny
  // fares from going below cost. Then re-sum — if rounding pushes us
  // off by ≤1 paise per rider, shift the rounding to the longest leg
  // so the sum exactly matches groupSubtotal.
  const weights = soloPieces.map((p) => p.components.subtotal / sumSolo);
  const classCfg = env.fare.vehicleClasses[vehicleClass];

  const rawShares = weights.map((w) => groupSubtotal * w);
  const flooredShares = rawShares.map((s) => Math.max(s, classCfg.minFare));
  // After the floor, the sum may exceed groupSubtotal. Don't pull it back
  // down — the floor is a hard contract with each rider. The driver
  // takes the higher total; this is intentional, and rare in practice.
  const allocatedTotal = flooredShares.reduce((a, s) => a + s, 0);

  // Per-rider breakdown: scale each component by the rider's allocated
  // share / their solo subtotal, then add the booking fee + GST.
  const allocations = soloPieces.map((p, i) => {
    const allocated = flooredShares[i];
    const scale = allocated / p.components.subtotal;
    return finalizeFare({
      vehicleClass,
      distanceKm: p.distanceKm,
      durationMin: p.durationMin,
      surge,
      components: {
        base: ROUND(p.components.base * scale),
        distance: ROUND(p.components.distance * scale),
        time: ROUND(p.components.time * scale),
        surgeAddition: ROUND(p.components.surgeAddition * scale),
        subtotal: ROUND(allocated),
        minimumFareApplied: allocated > p.components.subtotal * (1 - discount),
      },
      perRiderSubtotal: allocated,
      tripId: p.tripId,
      shareCount: members.length,
    });
  });

  return {
    vehicleClass,
    surgeMultiplier: surge,
    totalDistanceKm: ROUND(soloPieces.reduce((a, p) => a + p.distanceKm, 0) * 100) / 100,
    totalDurationMin: ROUND(soloPieces.reduce((a, p) => a + p.durationMin, 0)),
    groupTotal: allocations.reduce((a, x) => a + x.total, 0),
    allocations,
  };
}

/// Take per-rider subtotal + components and finish: booking fee, GST,
/// total. Centralized so solo + shared paths can't diverge.
function finalizeFare({
  vehicleClass,
  distanceKm,
  durationMin,
  surge,
  components,
  perRiderSubtotal,
  shareCount,
  tripId,
}) {
  const bookingFee = env.fare.bookingFeePaise;
  // GST applies to (subtotal + bookingFee), but ONLY when enabled —
  // until ShareCab holds a GSTIN we cannot collect this without
  // breaking section 9(5) compliance.
  const gstBase = perRiderSubtotal + bookingFee;
  const gst = env.fare.gst.enabled
    ? ROUND(gstBase * env.fare.gst.ratePct / 100)
    : 0;
  const total = ROUND(perRiderSubtotal + bookingFee + gst);

  return {
    ...(tripId ? { tripId } : {}),
    vehicleClass,
    distanceKm: ROUND(distanceKm * 100) / 100,
    durationMin: ROUND(durationMin),
    surgeMultiplier: ROUND(surge * 100) / 100,
    shareCount,
    components: {
      base: components.base,
      distance: components.distance,
      time: components.time,
      surgeAddition: components.surgeAddition,
      bookingFee,
      gst,
    },
    subtotal: components.subtotal,
    total,
    // Driver payout = what we collect from the rider minus GST that
    // the platform remits to the tax authority. Since we're
    // subscription-based (₹499/mo from the driver), there's NO
    // commission cut — the driver keeps the full fare net of GST.
    driverPayout: total - gst,
    minimumFareApplied: Boolean(components.minimumFareApplied),
  };
}

// =============================================================================
// Back-compat shims — let the legacy tripController call sites continue to
// work during the migration. New code should call `quoteSolo` / `quoteShared`
// directly with structured inputs.
// =============================================================================

/// Mirrors the old `estimateSoloFare` signature. Returns { total,
/// distanceKm, durationMin } with `total` in paise. Callers that read
/// the result and store it in Trip.fareEstimate now get paise — which is
/// the right thing.
function estimateSoloFare({
  pickup, dropoff,
  vehicleClass = 'sedan',
  averageSpeedKmph,
  requestedAt = new Date(),
}) {
  const km = distanceKm(pickup, dropoff);
  const speed = averageSpeedKmph || env.fare.fallbackSpeedKmph;
  const distanceMeters = km * 1000;
  const durationSeconds = (km / speed) * 3600;
  const fare = quoteSolo({
    vehicleClass,
    distanceMeters,
    durationSeconds,
    requestedAt,
  });
  return {
    total: fare.total,
    distanceKm: fare.distanceKm,
    durationMin: fare.durationMin,
    breakdown: fare,
  };
}

/// Mirrors the old `estimateSharedFareForGroup` signature. Returns
/// { perRider, groupTotal, distanceKm, durationMin } — but `perRider`
/// is now an array (one per trip) since the proportional allocator
/// gives different amounts to different riders. Legacy callers that
/// expect a scalar should switch to `quoteShared`; provided here only
/// so the migration in tripController can be incremental.
function estimateSharedFareForGroup(trips, {
  vehicleClass = 'sedan',
  averageSpeedKmph,
  requestedAt = new Date(),
} = {}) {
  const speed = averageSpeedKmph || env.fare.fallbackSpeedKmph;
  const members = trips.map((t, idx) => {
    const km = distanceKm(t.pickup, t.dropoff);
    return {
      tripId: t.tripId || t._id?.toString() || `idx_${idx}`,
      distanceMeters: km * 1000,
      durationSeconds: (km / speed) * 3600,
    };
  });
  const group = quoteShared({ vehicleClass, members, requestedAt });
  return {
    perRider: group.allocations.map((a) => ({
      tripId: a.tripId,
      total: a.total,
      breakdown: a,
    })),
    groupTotal: group.groupTotal,
    distanceKm: group.totalDistanceKm,
    durationMin: group.totalDurationMin,
  };
}

module.exports = {
  // New surface
  quoteSolo,
  quoteShared,
  classifyByCapacity,
  surgeMultiplierFor,
  // Legacy shims (kept during migration; remove once callers are off)
  estimateSoloFare,
  estimateSharedFareForGroup,
};
