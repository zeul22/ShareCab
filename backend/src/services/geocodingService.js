const env = require('../config/env');
const logger = require('../utils/logger');

// =============================================================================
// Reverse geocoding — coords → short human-readable name.
//
// Used by the rider app to label "Current location" with a real place
// (e.g. "Indiranagar, Bengaluru") the moment the GPS pin is captured.
// That way the trip is persisted with a meaningful pickup address and
// the rider history + analytics see proper names instead of every row
// reading "Current location".
//
// Wraps Google Maps Geocoding API with:
//   - 5-min in-memory cache keyed on 4-decimal coords (~10m). Repeat
//     lookups from the same neighbourhood share one upstream call.
//   - 5s abort so a slow Geocoding response can't tie up the request.
//   - Graceful fallback to a "lat, lng" string when the key is unset or
//     the API errors — the rider always gets *something* to show.
//
// Cost model: $5 / 1000 calls. With the coord-bucket cache, a single
// rider opening the app from their usual block costs one call/day max.
// =============================================================================

const CACHE_TTL_MS = 5 * 60 * 1000;
const cache = new Map(); // key: "lat,lng" (4 decimals) → { name, expiresAt }

async function reverseGeocode({ lat, lng }) {
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
    throw new Error('reverseGeocode: lat/lng must be finite numbers');
  }

  const key = `${lat.toFixed(4)},${lng.toFixed(4)}`;
  const cached = cache.get(key);
  if (cached && cached.expiresAt > Date.now()) {
    return cached.name;
  }

  // No API key configured — return a coord string so the caller still
  // has something to display. Logged at info, not warn, because this is
  // a valid local-dev mode.
  if (!env.googleMapsKey) {
    const name = formatFallback(lat, lng);
    cache.set(key, { name, expiresAt: Date.now() + CACHE_TTL_MS });
    return name;
  }

  try {
    const name = await callGoogleGeocoding({ lat, lng });
    cache.set(key, { name, expiresAt: Date.now() + CACHE_TTL_MS });
    return name;
  } catch (err) {
    logger.warn(`geocodingService: ${err.message || err} — falling back to coord string`);
    const name = formatFallback(lat, lng);
    cache.set(key, { name, expiresAt: Date.now() + CACHE_TTL_MS });
    return name;
  }
}

async function callGoogleGeocoding({ lat, lng }) {
  const params = new URLSearchParams({
    latlng: `${lat},${lng}`,
    key: env.googleMapsKey,
    // Bias to India so the formatted address comes out in
    // city/locality terms a rider here would recognise.
    region: 'in',
    // Drop the verbose components (postal codes, country codes, etc.)
    // to keep the response small.
    result_type: 'street_address|premise|neighborhood|sublocality|locality',
  });
  const url = `https://maps.googleapis.com/maps/api/geocode/json?${params.toString()}`;

  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), 5000);
  let body;
  try {
    const res = await fetch(url, { signal: ctrl.signal });
    if (!res.ok) {
      throw new Error(`Geocoding HTTP ${res.status}`);
    }
    body = await res.json();
  } finally {
    clearTimeout(timer);
  }

  if (body.status === 'ZERO_RESULTS') {
    return formatFallback(lat, lng);
  }
  if (body.status !== 'OK') {
    throw new Error(`Geocoding status=${body.status} msg="${body.error_message || ''}"`);
  }

  const results = Array.isArray(body.results) ? body.results : [];
  if (results.length === 0) {
    return formatFallback(lat, lng);
  }

  // Prefer a concise locality-style label over the full
  // postal-address blob. Walk the address_components for the
  // narrowest meaningful name + the city, then assemble.
  const r0 = results[0];
  const comps = Array.isArray(r0.address_components) ? r0.address_components : [];
  const byType = (...types) => {
    for (const t of types) {
      const c = comps.find((x) => x.types?.includes(t));
      if (c && c.short_name) return c.short_name;
    }
    return null;
  };
  const neighbourhood = byType('neighborhood', 'sublocality_level_1', 'sublocality');
  const locality = byType('locality', 'administrative_area_level_2');
  if (neighbourhood && locality && neighbourhood !== locality) {
    return `${neighbourhood}, ${locality}`;
  }
  if (neighbourhood) return neighbourhood;
  if (locality) return locality;
  // Last resort: the full formatted address.
  return r0.formatted_address || formatFallback(lat, lng);
}

function formatFallback(lat, lng) {
  return `${lat.toFixed(4)}, ${lng.toFixed(4)}`;
}

module.exports = { reverseGeocode };
