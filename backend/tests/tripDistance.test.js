/**
 * Trip-request distance sanity rails. These guards live in the zod
 * `superRefine` so they fire BEFORE any DB work — `requestTrip` /
 * `estimate` reject obviously-absurd trips (too close, identical
 * pickup+drop, or intercity-scale > maxDistanceKm) with a zod error
 * that the global errorHandler maps to 400. No real network or DB
 * needed; we just exercise the controller schema.
 */

const mongoose = require('mongoose');
const { MongoMemoryServer } = require('mongodb-memory-server');

const tripCtrl = require('../src/controllers/tripController');
const Trip = require('../src/models/Trip');
const User = require('../src/models/User');
const Unlock = require('../src/models/Unlock');
const env = require('../src/config/env');

function makeRes() {
  return {
    statusCode: 200,
    body: undefined,
    status(c) { this.statusCode = c; return this; },
    json(p) { this.body = p; return this; },
  };
}

async function call(handler, { auth, body }) {
  const req = { auth, body, params: {} };
  const res = makeRes();
  let nextErr;
  await handler(req, res, (err) => { nextErr = err; });
  return { res, err: nextErr };
}

// Bengaluru anchor — all test points sit inside the India bbox so the
// distance guard is what's actually being exercised.
const BLR = { lat: 12.9716, lng: 77.5946 };

// 1 km ≈ 0.009° latitude near BLR.
function pointKmAway(km) {
  return { lat: BLR.lat + km * 0.009, lng: BLR.lng };
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
  await Unlock.deleteMany({});
});

async function makeRiderWithUnlock() {
  const rider = await User.create({
    name: 'Rider',
    phone: `+9199${Math.floor(Math.random() * 1e8).toString().padStart(8, '0')}`,
    role: 'rider',
    passwordHash: 'unused',
  });
  // requestTrip's shareEnabled path needs an unconsumed unlock —
  // without it the trip is rejected for unrelated reasons (402).
  await Unlock.create({
    rider: rider._id,
    source: 'ad',
    usedAt: null,
    expiresAt: new Date(Date.now() + 60 * 60 * 1000),
  });
  return rider;
}

describe('Trip distance sanity rails', () => {
  test('rejects pickup == drop (zero distance)', async () => {
    const rider = await makeRiderWithUnlock();
    const r = await call(tripCtrl.requestTrip, {
      auth: { userId: rider._id.toString(), role: 'rider' },
      body: {
        pickup: { address: 'A', ...BLR },
        dropoff: { address: 'A', ...BLR },
        shareEnabled: true,
      },
    });
    expect(r.err).toBeDefined();
    // ZodError surfaces with statusCode 400 via the global errorHandler.
    expect(String(r.err.message)).toMatch(/too close/i);
    expect(await Trip.countDocuments()).toBe(0);
  });

  test('rejects sub-300m trips by default', async () => {
    const rider = await makeRiderWithUnlock();
    const r = await call(tripCtrl.requestTrip, {
      auth: { userId: rider._id.toString(), role: 'rider' },
      body: {
        pickup: { address: 'A', ...BLR },
        dropoff: { address: 'B', ...pointKmAway(0.1) }, // ~100m
        shareEnabled: true,
      },
    });
    expect(r.err).toBeDefined();
    expect(String(r.err.message)).toMatch(/too close/i);
  });

  test('rejects intercity-scale trips > maxDistanceKm', async () => {
    const rider = await makeRiderWithUnlock();
    const r = await call(tripCtrl.requestTrip, {
      auth: { userId: rider._id.toString(), role: 'rider' },
      body: {
        pickup: { address: 'A', ...BLR },
        dropoff: { address: 'B', ...pointKmAway(env.trip.maxDistanceKm + 5) },
        shareEnabled: true,
      },
    });
    expect(r.err).toBeDefined();
    expect(String(r.err.message)).toMatch(/too far/i);
  });

  test('accepts a normal short city trip (~5 km)', async () => {
    const rider = await makeRiderWithUnlock();
    const r = await call(tripCtrl.requestTrip, {
      auth: { userId: rider._id.toString(), role: 'rider' },
      body: {
        pickup: { address: 'A', ...BLR },
        dropoff: { address: 'B', ...pointKmAway(5) },
        shareEnabled: true,
      },
    });
    expect(r.err).toBeUndefined();
    expect(await Trip.countDocuments()).toBe(1);
  });

  test('estimate rejects the same bad cases without touching DB', async () => {
    const r = await call(tripCtrl.estimate, {
      auth: { userId: 'anyone', role: 'rider' },
      body: {
        pickup: { ...BLR },
        dropoff: pointKmAway(env.trip.maxDistanceKm + 1),
      },
    });
    expect(r.err).toBeDefined();
    expect(String(r.err.message)).toMatch(/too far/i);
  });
});
