const { distanceKm, toGeoJSONPoint, fromGeoJSONPoint } = require('../src/utils/geo');
const { _internals: { centroidOf } } = require('../src/services/matchingService');

describe('distanceKm', () => {
  test('same point is zero', () => {
    expect(distanceKm({ lat: 12.97, lng: 77.59 }, { lat: 12.97, lng: 77.59 })).toBe(0);
  });

  test('roughly matches known city pair (NYC ↔ LA ≈ 3936 km)', () => {
    const nyc = { lat: 40.7128, lng: -74.006 };
    const la = { lat: 34.0522, lng: -118.2437 };
    expect(distanceKm(nyc, la)).toBeGreaterThan(3900);
    expect(distanceKm(nyc, la)).toBeLessThan(3970);
  });

  test('symmetric', () => {
    const a = { lat: 12.9716, lng: 77.5946 };
    const b = { lat: 12.9352, lng: 77.6245 };
    expect(distanceKm(a, b)).toBeCloseTo(distanceKm(b, a), 9);
  });

  test('two points ~1km apart in Bengaluru', () => {
    // ~0.009° latitude ≈ 1 km
    const a = { lat: 12.9700, lng: 77.5946 };
    const b = { lat: 12.9790, lng: 77.5946 };
    expect(distanceKm(a, b)).toBeGreaterThan(0.95);
    expect(distanceKm(a, b)).toBeLessThan(1.05);
  });
});

describe('GeoJSON helpers', () => {
  test('toGeoJSONPoint puts coordinates in [lng, lat] order', () => {
    expect(toGeoJSONPoint({ lat: 12.97, lng: 77.59 })).toEqual({
      type: 'Point',
      coordinates: [77.59, 12.97],
    });
  });

  test('fromGeoJSONPoint reverses the order back', () => {
    expect(fromGeoJSONPoint({ type: 'Point', coordinates: [77.59, 12.97] })).toEqual({
      lat: 12.97,
      lng: 77.59,
    });
  });

  test('fromGeoJSONPoint returns null for malformed input', () => {
    expect(fromGeoJSONPoint(null)).toBeNull();
    expect(fromGeoJSONPoint({})).toBeNull();
    expect(fromGeoJSONPoint({ coordinates: 'nope' })).toBeNull();
  });

  test('round-trip preserves the point', () => {
    const p = { lat: 12.9352, lng: 77.6245 };
    expect(fromGeoJSONPoint(toGeoJSONPoint(p))).toEqual(p);
  });
});

describe('centroidOf', () => {
  test('single point is its own centroid', () => {
    expect(centroidOf([{ lat: 10, lng: 20 }])).toEqual({ lat: 10, lng: 20 });
  });

  test('midpoint of two points', () => {
    expect(centroidOf([
      { lat: 0, lng: 0 },
      { lat: 10, lng: 20 },
    ])).toEqual({ lat: 5, lng: 10 });
  });

  test('average of three points', () => {
    const c = centroidOf([
      { lat: 0, lng: 0 },
      { lat: 3, lng: 6 },
      { lat: 6, lng: 12 },
    ]);
    expect(c.lat).toBeCloseTo(3, 9);
    expect(c.lng).toBeCloseTo(6, 9);
  });
});
