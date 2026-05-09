const { distanceKm, toGeoJSONPoint, fromGeoJSONPoint, isWithinIndia, INDIA_BOUNDS } = require('../src/utils/geo');
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

describe('isWithinIndia', () => {
  test.each([
    ['Bengaluru', { lat: 12.9716, lng: 77.5946 }],
    ['Delhi', { lat: 28.6139, lng: 77.2090 }],
    ['Mumbai', { lat: 19.0760, lng: 72.8777 }],
    ['Srinagar (north)', { lat: 34.0837, lng: 74.7973 }],
    ['Kanyakumari (south)', { lat: 8.0883, lng: 77.5385 }],
    ['Port Blair (east)', { lat: 11.6234, lng: 92.7265 }],
  ])('%s is within India', (_name, p) => {
    expect(isWithinIndia(p)).toBe(true);
  });

  test.each([
    ['London', { lat: 51.5074, lng: -0.1278 }],                // negative lng
    ['New York', { lat: 40.7128, lng: -74.0060 }],
    ['Singapore', { lat: 1.3521, lng: 103.8198 }],             // east of India bounds
    ['Origin (0,0)', { lat: 0, lng: 0 }],
    ['Tehran', { lat: 35.6892, lng: 51.3890 }],                // west of India bounds
  ])('%s is rejected', (_name, p) => {
    expect(isWithinIndia(p)).toBe(false);
  });

  // Known limitation: a rectangular bounding box can't separate Sri Lanka,
  // Bangladesh, or southern Nepal — they sit inside India's lat/lng range.
  // For MVP this is acceptable (we're guarding against obvious off-region
  // requests, not policing borders). Switch to a polygon check + turf.js if
  // tighter validation is ever needed.
  test('does not exclude near-border neighboring states (documented limitation)', () => {
    expect(isWithinIndia({ lat: 6.9271, lng: 79.8612 })).toBe(true); // Colombo
  });

  test('exposes the bounding box constants', () => {
    expect(INDIA_BOUNDS).toMatchObject({
      latMin: expect.any(Number),
      latMax: expect.any(Number),
      lngMin: expect.any(Number),
      lngMax: expect.any(Number),
    });
    expect(INDIA_BOUNDS.latMin).toBeLessThan(INDIA_BOUNDS.latMax);
    expect(INDIA_BOUNDS.lngMin).toBeLessThan(INDIA_BOUNDS.lngMax);
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
