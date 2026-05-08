const EARTH_RADIUS_KM = 6371;

function toRad(deg) {
  return (deg * Math.PI) / 180;
}

/**
 * Haversine distance between two {lat, lng} points, in km.
 * Used by the matching engine to compare pickup and drop locations.
 */
function distanceKm(a, b) {
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const lat1 = toRad(a.lat);
  const lat2 = toRad(b.lat);

  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_KM * Math.asin(Math.sqrt(h));
}

function toGeoJSONPoint({ lat, lng }) {
  return { type: 'Point', coordinates: [lng, lat] };
}

function fromGeoJSONPoint(point) {
  if (!point || !Array.isArray(point.coordinates)) return null;
  const [lng, lat] = point.coordinates;
  return { lat, lng };
}

module.exports = { distanceKm, toGeoJSONPoint, fromGeoJSONPoint };
