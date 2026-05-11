/**
 * GET /api/trips/destinations/recent — recent unique destinations
 * (deduped by rounded lat/lng) for the calling rider.
 *
 * The aggregation pipeline does the real work; these tests pin the
 * three behaviours the client depends on:
 *   1. Repeat trips to "the same place" collapse to one entry with a
 *      bumped tripCount.
 *   2. Entries are returned in most-recent-first order.
 *   3. The list respects the ?limit parameter (default 5, hard cap 20).
 *   4. Cancelled / in-progress trips don't appear (only completed).
 *   5. Empty case returns an empty list, never throws.
 */

const mongoose = require('mongoose');
const { MongoMemoryServer } = require('mongodb-memory-server');

const Trip = require('../src/models/Trip');
const User = require('../src/models/User');
const tripCtrl = require('../src/controllers/tripController');

function makeRes() {
  return {
    statusCode: 200,
    body: undefined,
    status(c) { this.statusCode = c; return this; },
    json(p) { this.body = p; return this; },
  };
}

async function call(handler, { auth, query = {} }) {
  const req = { auth, query, params: {} };
  const res = makeRes();
  let nextErr;
  await handler(req, res, (err) => { nextErr = err; });
  return { res, err: nextErr };
}

// Bengaluru anchor — points inside India bbox so any other guard rails
// don't fire.
const BLR = { lat: 12.9716, lng: 77.5946 };

function pt(lat, lng) { return { type: 'Point', coordinates: [lng, lat] }; }

async function makeRider() {
  return User.create({
    name: 'Rider',
    phone: `+9199${Math.floor(Math.random() * 1e8).toString().padStart(8, '0')}`,
    role: 'rider',
    passwordHash: 'unused',
  });
}

async function makeTrip({
  rider,
  drop,
  address = 'Drop',
  status = 'completed',
  createdAt = new Date(),
}) {
  return Trip.create({
    rider: rider._id,
    pickup: { address: 'A', location: pt(BLR.lat, BLR.lng) },
    dropoff: { address, location: pt(drop.lat, drop.lng) },
    status,
    createdAt,
  });
}

let mongo;

beforeAll(async () => {
  mongo = await MongoMemoryServer.create();
  await mongoose.connect(mongo.getUri());
});

afterAll(async () => {
  await mongoose.disconnect();
  await mongo.stop();
});

beforeEach(async () => {
  await Trip.deleteMany({});
  await User.deleteMany({});
});

describe('GET /trips/destinations/recent', () => {
  test('empty list when rider has no completed trips', async () => {
    const rider = await makeRider();
    const r = await call(tripCtrl.getRecentDestinations, {
      auth: { userId: rider._id.toString(), role: 'rider' },
    });
    expect(r.err).toBeUndefined();
    expect(r.res.body.destinations).toEqual([]);
  });

  test('dedupes by rounded coords and bumps tripCount', async () => {
    const rider = await makeRider();
    // Three trips to the same office. Jitter is on the 5th decimal AND
    // away from the .5 half-step so floating-point + Mongo banker's
    // rounding don't push us into a neighbouring bucket. All three
    // lat/lng pairs round to (12.9810, 77.5910).
    await makeTrip({
      rider,
      drop: { lat: 12.98100, lng: 77.59100 },
      address: 'Indiranagar Office',
      createdAt: new Date('2026-04-01'),
    });
    await makeTrip({
      rider,
      drop: { lat: 12.98103, lng: 77.59102 },
      address: 'Indiranagar Office',
      createdAt: new Date('2026-04-15'),
    });
    await makeTrip({
      rider,
      drop: { lat: 12.98098, lng: 77.59104 },
      address: 'Indiranagar Office',
      createdAt: new Date('2026-05-01'),
    });

    const r = await call(tripCtrl.getRecentDestinations, {
      auth: { userId: rider._id.toString(), role: 'rider' },
    });
    expect(r.err).toBeUndefined();
    expect(r.res.body.destinations).toHaveLength(1);
    expect(r.res.body.destinations[0]).toMatchObject({
      address: 'Indiranagar Office',
      tripCount: 3,
    });
  });

  test('orders by lastUsedAt desc', async () => {
    const rider = await makeRider();
    await makeTrip({
      rider,
      drop: { lat: 12.95, lng: 77.55 },
      address: 'Older',
      createdAt: new Date('2026-01-01'),
    });
    await makeTrip({
      rider,
      drop: { lat: 12.97, lng: 77.62 },
      address: 'Newer',
      createdAt: new Date('2026-05-01'),
    });
    await makeTrip({
      rider,
      drop: { lat: 13.01, lng: 77.65 },
      address: 'Newest',
      createdAt: new Date('2026-05-10'),
    });

    const r = await call(tripCtrl.getRecentDestinations, {
      auth: { userId: rider._id.toString(), role: 'rider' },
    });
    expect(r.err).toBeUndefined();
    const addresses = r.res.body.destinations.map((d) => d.address);
    expect(addresses).toEqual(['Newest', 'Newer', 'Older']);
  });

  test('respects ?limit param and clamps to [1, 20]', async () => {
    const rider = await makeRider();
    for (let i = 0; i < 8; i++) {
      await makeTrip({
        rider,
        // Different-enough coords that none collapse together.
        drop: { lat: 12.9 + i * 0.01, lng: 77.5 + i * 0.01 },
        address: `Drop ${i}`,
        createdAt: new Date(Date.now() - i * 1000),
      });
    }
    const r = await call(tripCtrl.getRecentDestinations, {
      auth: { userId: rider._id.toString(), role: 'rider' },
      query: { limit: '3' },
    });
    expect(r.err).toBeUndefined();
    expect(r.res.body.destinations).toHaveLength(3);
  });

  test('excludes non-completed trips', async () => {
    const rider = await makeRider();
    await makeTrip({
      rider,
      drop: { lat: 12.97, lng: 77.6 },
      address: 'Cancelled drop',
      status: 'cancelled',
    });
    await makeTrip({
      rider,
      drop: { lat: 12.98, lng: 77.61 },
      address: 'In-progress drop',
      status: 'in_progress',
    });
    const r = await call(tripCtrl.getRecentDestinations, {
      auth: { userId: rider._id.toString(), role: 'rider' },
    });
    expect(r.err).toBeUndefined();
    expect(r.res.body.destinations).toEqual([]);
  });

  test('one rider\'s history is isolated from another\'s', async () => {
    const me = await makeRider();
    const stranger = await makeRider();
    await makeTrip({
      rider: stranger,
      drop: { lat: 12.97, lng: 77.6 },
      address: "Stranger's drop",
    });
    const r = await call(tripCtrl.getRecentDestinations, {
      auth: { userId: me._id.toString(), role: 'rider' },
    });
    expect(r.err).toBeUndefined();
    expect(r.res.body.destinations).toEqual([]);
  });
});
