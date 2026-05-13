const { z } = require('zod');
const geocodingService = require('../services/geocodingService');
const { HttpError } = require('../middleware/errorHandler');

// =============================================================================
// Reverse-geocode coords to a short, human-readable name.
//
// Auth is required because the underlying Google Geocoding API costs
// money. Leaving it open would let anyone grind our quota by pinging it
// in a loop. Per-rider rate limiting is a follow-up.
//
// Body shape kept tiny — just lat + lng — so the rider app can call
// this synchronously the moment it captures a GPS fix.
// =============================================================================

const reverseSchema = z.object({
  lat: z.number().finite().min(-90).max(90),
  lng: z.number().finite().min(-180).max(180),
});

async function reverseGeocode(req, res, next) {
  try {
    const parsed = reverseSchema.safeParse({
      lat: Number(req.query.lat ?? req.body?.lat),
      lng: Number(req.query.lng ?? req.body?.lng),
    });
    if (!parsed.success) {
      throw new HttpError(400, 'lat + lng required (finite numbers, in valid range)');
    }
    const { lat, lng } = parsed.data;
    const name = await geocodingService.reverseGeocode({ lat, lng });
    // 5-min cache header mirrors the in-memory cache TTL; the rider
    // app can opportunistically reuse the response across rebuilds.
    res.set('Cache-Control', 'private, max-age=300');
    res.json({ name, lat, lng });
  } catch (err) {
    next(err);
  }
}

module.exports = { reverseGeocode };
