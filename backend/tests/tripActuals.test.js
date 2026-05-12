/**
 * Trip actuals capture — actualPickup + actualDropoff get persisted when
 * the driver app passes GPS coords to `markPickedUp` / `markDropped`.
 *
 * Backward-compatible: when the driver omits coords (older app build),
 * the lifecycle still advances, just without actuals.
 */

const mongoose = require('mongoose');
const { MongoMemoryServer } = require('mongodb-memory-server');

const Trip = require('../src/models/Trip');
const Driver = require('../src/models/Driver');
const User = require('../src/models/User');
const tripCtrl = require('../src/controllers/tripController');

const BLR = { lat: 12.9716, lng: 77.5946 };
const BLR_NEAR_PICKUP = { lat: 12.9720, lng: 77.5950 }; // ~50m away
const BLR_DROP = { lat: 12.9352, lng: 77.6245 };

function pt({ lat, lng }) {
  return { type: 'Point', coordinates: [lng, lat] };
}
function makeRes() {
  return {
    statusCode: 200, body: undefined,
    status(c) { this.statusCode = c; return this; },
    json(p) { this.body = p; return this; },
  };
}
async function call(handler, { auth, params = {}, body = {} } = {}) {
  const req = { auth, params, body, headers: {} };
  const res = makeRes();
  let nextErr;
  await handler(req, res, (err) => { nextErr = err; });
  return { res, err: nextErr };
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
  await Driver.deleteMany({});
  await User.deleteMany({});
});

async function setupDispatchedTrip() {
  const user = await User.create({
    name: 'Driver',
    phone: `+9199999${Math.floor(Math.random() * 1e5).toString().padStart(5, '0')}`,
    role: 'driver',
    passwordHash: 'unused',
  });
  const driver = await Driver.create({
    user: user._id,
    licenseNumber: 'KA01-DL-0001',
    vehicle: { model: 'Dzire', plate: 'KA011234', color: 'White', capacity: 4 },
    isOnline: true,
    subscriptionStartedAt: new Date(),
    subscriptionExpiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
    subscriptionPaymentRef: 'free-trial',
  });
  const rider = await User.create({
    name: 'Rider',
    phone: `+9198888${Math.floor(Math.random() * 1e5).toString().padStart(5, '0')}`,
    role: 'rider',
    passwordHash: 'unused',
  });
  const trip = await Trip.create({
    rider: rider._id,
    driver: driver._id,
    pickup: { address: 'BLR', location: pt(BLR) },
    dropoff: { address: 'Koramangala', location: pt(BLR_DROP) },
    status: 'arriving',
    fareEstimate: 20000,
  });
  driver.activeTrips = [trip._id];
  await driver.save();
  return { user, driver, trip };
}

describe('actualPickup persistence', () => {
  test('persists actualPickup when driver passes GPS', async () => {
    const { user, trip } = await setupDispatchedTrip();
    const { err } = await call(tripCtrl.pickUpRider, {
      auth: { userId: user._id.toString(), role: 'driver' },
      params: { id: trip._id.toString() },
      body: BLR_NEAR_PICKUP,
    });
    expect(err).toBeUndefined();
    const reloaded = await Trip.findById(trip._id);
    expect(reloaded.status).toBe('in_progress');
    expect(reloaded.actualPickup.location.coordinates).toEqual(
      [BLR_NEAR_PICKUP.lng, BLR_NEAR_PICKUP.lat],
    );
    expect(reloaded.actualPickup.recordedAt).toBeInstanceOf(Date);
  });

  test('omits actualPickup when driver does not pass GPS (backward compat)', async () => {
    const { user, trip } = await setupDispatchedTrip();
    const { err } = await call(tripCtrl.pickUpRider, {
      auth: { userId: user._id.toString(), role: 'driver' },
      params: { id: trip._id.toString() },
      body: {},
    });
    expect(err).toBeUndefined();
    const reloaded = await Trip.findById(trip._id);
    expect(reloaded.status).toBe('in_progress');
    // No coords supplied → Mongoose initializes the empty array default,
    // but `recordedAt` stays unset, which is the signal "no actual captured."
    expect(reloaded.actualPickup?.recordedAt).toBeFalsy();
    expect(reloaded.actualPickup?.location?.coordinates?.length || 0).toBe(0);
  });

  test('rejects out-of-India coords with a 400', async () => {
    const { user, trip } = await setupDispatchedTrip();
    const { err } = await call(tripCtrl.pickUpRider, {
      auth: { userId: user._id.toString(), role: 'driver' },
      params: { id: trip._id.toString() },
      body: { lat: 40.7128, lng: -74.006 }, // NYC
    });
    expect(err).toBeDefined();
    // Trip stays in arriving — no partial mutation.
    const reloaded = await Trip.findById(trip._id);
    expect(reloaded.status).toBe('arriving');
  });
});

describe('actualDropoff persistence', () => {
  test('persists actualDropoff when driver passes GPS', async () => {
    const { user, trip } = await setupDispatchedTrip();
    // First pickup so status becomes in_progress.
    await call(tripCtrl.pickUpRider, {
      auth: { userId: user._id.toString(), role: 'driver' },
      params: { id: trip._id.toString() },
      body: BLR_NEAR_PICKUP,
    });
    const dropCoords = { lat: 12.9355, lng: 77.6240 }; // near requested drop
    const { err } = await call(tripCtrl.dropOffRider, {
      auth: { userId: user._id.toString(), role: 'driver' },
      params: { id: trip._id.toString() },
      body: dropCoords,
    });
    expect(err).toBeUndefined();
    const reloaded = await Trip.findById(trip._id);
    expect(reloaded.status).toBe('completed');
    expect(reloaded.actualDropoff.location.coordinates).toEqual(
      [dropCoords.lng, dropCoords.lat],
    );
  });
});
