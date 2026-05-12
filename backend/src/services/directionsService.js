const env = require('../config/env');
const { distanceKm } = require('../utils/geo');
const logger = require('../utils/logger');

// =============================================================================
// Server-side Google Directions wrapper for the fare engine.
//
// Why server-side: we can't trust client-supplied distance/duration for
// billing — riders could "estimate" a 50 km trip as 5 km and underpay.
// The server calls Directions independently and uses Google's result.
//
// When the API is unconfigured / unreachable / returns ZERO_RESULTS,
// we fall back to a haversine straight-line distance with a fixed
// fallback speed from env. The trip still prices reasonably, just less
// accurately for time-in-traffic.
//
// In-memory cache by stop fingerprint with a short TTL — different
// requests in the same minute for the same route share one upstream
// call. No Redis at this scale; restart wipes the cache and that's fine.
// =============================================================================

const CACHE_TTL_MS = 5 * 60 * 1000;
const cache = new Map(); // key: fingerprint → { result, expiresAt }

/// Fetch the road-following route through [stops]. Each stop is `{ lat, lng }`.
/// Returns:
///   {
///     distanceMeters,
///     durationSeconds,
///     source: 'directions' | 'haversine',
///   }
async function route(stops) {
  if (!Array.isArray(stops) || stops.length < 2) {
    throw new Error('directionsService.route: need at least 2 stops');
  }

  const fp = fingerprint(stops);
  const cached = cache.get(fp);
  if (cached && cached.expiresAt > Date.now()) {
    return cached.result;
  }

  // No key → haversine fallback. Logged at info, not warn — this is a
  // valid deployment mode (dev without a key, or a deliberate cost cut).
  if (!env.googleMapsKey) {
    const result = haversineFallback(stops);
    cache.set(fp, { result, expiresAt: Date.now() + CACHE_TTL_MS });
    return result;
  }

  try {
    const result = await callDirections(stops);
    cache.set(fp, { result, expiresAt: Date.now() + CACHE_TTL_MS });
    return result;
  } catch (err) {
    // Surface the API failure once but don't block trip pricing.
    logger.warn(`directionsService: ${err.message || err} — falling back to haversine`);
    const result = haversineFallback(stops);
    cache.set(fp, { result, expiresAt: Date.now() + CACHE_TTL_MS });
    return result;
  }
}

async function callDirections(stops) {
  const origin = stops[0];
  const destination = stops[stops.length - 1];
  const waypoints = stops.slice(1, -1);

  const params = new URLSearchParams({
    origin: `${origin.lat},${origin.lng}`,
    destination: `${destination.lat},${destination.lng}`,
    mode: 'driving',
    key: env.googleMapsKey,
  });
  if (waypoints.length > 0) {
    params.set(
      'waypoints',
      waypoints.map((w) => `${w.lat},${w.lng}`).join('|'),
    );
  }
  const url = `https://maps.googleapis.com/maps/api/directions/json?${params.toString()}`;

  // Use the built-in fetch (Node 18+). Cap the call so a slow Directions
  // response can't tie up the trip-request thread.
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), 5000);
  let body;
  try {
    const res = await fetch(url, { signal: ctrl.signal });
    if (!res.ok) {
      throw new Error(`Directions HTTP ${res.status}`);
    }
    body = await res.json();
  } finally {
    clearTimeout(timer);
  }

  if (body.status !== 'OK') {
    throw new Error(
      `Directions status=${body.status} msg="${body.error_message || ''}"`,
    );
  }
  const route0 = body.routes && body.routes[0];
  if (!route0 || !Array.isArray(route0.legs) || route0.legs.length === 0) {
    throw new Error('Directions returned empty route');
  }

  // Sum across legs — multi-stop trips have one leg per pickup→drop segment.
  const distanceMeters = route0.legs.reduce(
    (sum, leg) => sum + (leg.distance?.value || 0),
    0,
  );
  const durationSeconds = route0.legs.reduce(
    (sum, leg) => sum + (leg.duration?.value || 0),
    0,
  );
  return { distanceMeters, durationSeconds, source: 'directions' };
}

function haversineFallback(stops) {
  let totalKm = 0;
  for (let i = 1; i < stops.length; i += 1) {
    totalKm += distanceKm(stops[i - 1], stops[i]);
  }
  const speed = env.fare.fallbackSpeedKmph;
  const durationSeconds = (totalKm / speed) * 3600;
  return {
    distanceMeters: Math.round(totalKm * 1000),
    durationSeconds: Math.round(durationSeconds),
    source: 'haversine',
  };
}

/// 5-decimal precision (~1m) so trivial coord jitter doesn't bust the
/// cache. Order matters — same stops in reverse order are a different
/// route in driving.
function fingerprint(stops) {
  return stops
    .map((s) => `${s.lat.toFixed(5)},${s.lng.toFixed(5)}`)
    .join('|');
}

module.exports = { route };
