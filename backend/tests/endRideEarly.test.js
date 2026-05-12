/**
 * Rider-initiated "end ride here" — drops the rider at their current
 * location while in_progress, charges the FULL pre-quoted fareEstimate
 * (no proration), pulls THIS trip from the driver's activeTrips,
 * leaves siblings alone in shared trips.
 */

const mongoose = require('mongoose');
const { MongoMemoryServer } = require('mongodb-memory-server');

const Trip = require('../src/models/Trip');
const Driver = require('../src/models/Driver');
const User = require('../src/models/User');
const MatchGroup = require('../src/models/MatchGroup');
const tripCtrl = require('../src/controllers/tripController');

const BLR = { lat: 12.9716, lng: 77.5946 };
function pt({ lat, lng }) { return { type: 'Point', coordinates: [lng, lat] }; }
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
  await MatchGroup.deleteMany({});
});

async function setupInProgressTrip({ withDriver = true, matchGroup = null } = {}) {
  const rider = await User.create({
    name: 'Rider',
    phone: `+9198${String(Math.random()).slice(2, 10)}`,
    role: 'rider',
    passwordHash: 'x',
  });
  let driver = null;
  if (withDriver) {
    const dUser = await User.create({
      name: 'Driver',
      phone: `+9197${String(Math.random()).slice(2, 10)}`,
      role: 'driver',
      passwordHash: 'x',
    });
    driver = await Driver.create({
      user: dUser._id,
      licenseNumber: 'KA01-1',
      vehicle: { model: 'Dzire', plate: 'KA01XX', color: 'White', capacity: 4 },
    });
  }
  const trip = await Trip.create({
    rider: rider._id,
    driver: driver?._id || null,
    matchGroup: matchGroup?._id || null,
    pickup: { address: 'BLR', location: pt(BLR) },
    dropoff: {
      address: 'Drop',
      location: pt({ lat: BLR.lat + 0.05, lng: BLR.lng + 0.05 }),
    },
    status: 'in_progress',
    startedAt: new Date(),
    fareEstimate: 17500, // ₹175 in paise
  });
  if (driver) {
    driver.activeTrips = [trip._id];
    await driver.save();
  }
  return { rider, driver, trip };
}

describe('POST /trips/:id/end-early', () => {
  test('charges fareFinal = fareEstimate (full, no proration)', async () => {
    const { rider, trip } = await setupInProgressTrip();
    const { res, err } = await call(tripCtrl.endRideEarly, {
      auth: { userId: rider._id.toString(), role: 'rider' },
      params: { id: trip._id.toString() },
    });
    expect(err).toBeUndefined();
    const reloaded = await Trip.findById(trip._id);
    expect(reloaded.status).toBe('completed');
    expect(reloaded.fareFinal).toBe(17500); // = fareEstimate
    expect(reloaded.completedAt).toBeInstanceOf(Date);
    expect(res.body.trip._id.toString()).toBe(trip._id.toString());
  });

  test('pulls THIS trip from driver.activeTrips, leaves siblings', async () => {
    const { rider, driver, trip } = await setupInProgressTrip();
    // Add a sibling so we can verify only `trip` was pulled.
    const siblingRider = await User.create({
      name: 'Other',
      phone: `+9196${String(Math.random()).slice(2, 10)}`,
      role: 'rider', passwordHash: 'x',
    });
    const sibling = await Trip.create({
      rider: siblingRider._id,
      driver: driver._id,
      pickup: { address: 'p', location: pt(BLR) },
      dropoff: { address: 'd', location: pt({ lat: BLR.lat + 0.02, lng: BLR.lng + 0.02 }) },
      status: 'in_progress',
      fareEstimate: 12000,
    });
    driver.activeTrips = [trip._id, sibling._id];
    await driver.save();

    await call(tripCtrl.endRideEarly, {
      auth: { userId: rider._id.toString(), role: 'rider' },
      params: { id: trip._id.toString() },
    });

    const dReloaded = await Driver.findById(driver._id);
    expect(dReloaded.activeTrips.map(String)).toEqual([sibling._id.toString()]);
    // Sibling status untouched.
    const sReloaded = await Trip.findById(sibling._id);
    expect(sReloaded.status).toBe('in_progress');
  });

  test('rejects when status is not in_progress', async () => {
    const { rider, trip } = await setupInProgressTrip();
    trip.status = 'arriving';
    await trip.save();
    const { err } = await call(tripCtrl.endRideEarly, {
      auth: { userId: rider._id.toString(), role: 'rider' },
      params: { id: trip._id.toString() },
    });
    expect(err).toBeDefined();
    expect(err.status).toBe(409);
  });

  test('403 when the requester is not the rider', async () => {
    const { trip } = await setupInProgressTrip();
    const other = await User.create({
      name: 'Other', phone: `+9195${String(Math.random()).slice(2, 10)}`,
      role: 'rider', passwordHash: 'x',
    });
    const { err } = await call(tripCtrl.endRideEarly, {
      auth: { userId: other._id.toString(), role: 'rider' },
      params: { id: trip._id.toString() },
    });
    expect(err).toBeDefined();
    expect(err.status).toBe(403);
  });

  test('idempotent when called on an already-completed trip', async () => {
    const { rider, trip } = await setupInProgressTrip();
    trip.status = 'completed';
    trip.fareFinal = 17500;
    await trip.save();
    const { res, err } = await call(tripCtrl.endRideEarly, {
      auth: { userId: rider._id.toString(), role: 'rider' },
      params: { id: trip._id.toString() },
    });
    expect(err).toBeUndefined();
    expect(res.body.alreadyEnded).toBe(true);
  });
});
