/**
 * GET /trips/:id/driver-location — rider-side live driver position + ETA.
 *
 * Asserts:
 *   - 404 before a driver is assigned (rider-only mode pre-match,
 *     or matched-but-not-yet-dispatched).
 *   - 403 when a different rider asks for someone else's trip.
 *   - Returns driver coords + ETA in arriving status.
 *   - Returns no ETA in non-active statuses.
 *   - Uses haversine fallback when GOOGLE_MAPS_KEY is unset (default test env).
 */

const mongoose = require('mongoose');
const { MongoMemoryServer } = require('mongodb-memory-server');

const Trip = require('../src/models/Trip');
const Driver = require('../src/models/Driver');
const User = require('../src/models/User');
const tripCtrl = require('../src/controllers/tripController');

const BLR = { lat: 12.9716, lng: 77.5946 };
const DRIVER_POS = { lat: 12.9650, lng: 77.5980 }; // ~1 km from BLR

function pt({ lat, lng }) {
  return { type: 'Point', coordinates: [lng, lat] };
}
function makeRes() {
  return {
    statusCode: 200, body: undefined, headers: {},
    status(c) { this.statusCode = c; return this; },
    json(p) { this.body = p; return this; },
    set(_k, _v) { return this; },
  };
}
async function call(handler, { auth, params = {} } = {}) {
  const req = { auth, params, headers: {} };
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

async function makeTrip({ status = 'arriving', withDriver = true, driverLocation = DRIVER_POS } = {}) {
  const rider = await User.create({
    name: 'Rider',
    phone: `+9198888${Math.floor(Math.random() * 1e5).toString().padStart(5, '0')}`,
    role: 'rider',
    passwordHash: 'unused',
  });
  let driver = null;
  if (withDriver) {
    const dUser = await User.create({
      name: 'Driver',
      phone: `+9197777${Math.floor(Math.random() * 1e5).toString().padStart(5, '0')}`,
      role: 'driver',
      passwordHash: 'unused',
    });
    driver = await Driver.create({
      user: dUser._id,
      licenseNumber: 'KA01-1',
      vehicle: { model: 'Dzire', plate: 'KA01XX', color: 'White', capacity: 4 },
      currentLocation: pt(driverLocation),
    });
  }
  const trip = await Trip.create({
    rider: rider._id,
    driver: driver?._id || null,
    pickup: { address: 'BLR', location: pt(BLR) },
    dropoff: { address: 'Drop', location: pt({ lat: BLR.lat + 0.05, lng: BLR.lng + 0.05 }) },
    status,
    fareEstimate: 15000,
  });
  return { rider, driver, trip };
}

describe('GET /trips/:id/driver-location', () => {
  test('404 when no driver is assigned yet', async () => {
    const { rider, trip } = await makeTrip({ withDriver: false, status: 'requested' });
    const { res, err } = await call(tripCtrl.getDriverLocation, {
      auth: { userId: rider._id.toString(), role: 'rider' },
      params: { id: trip._id.toString() },
    });
    expect(err).toBeDefined();
    expect(err.status).toBe(404);
    expect(res.body).toBeUndefined();
  });

  test('403 when a different user requests', async () => {
    const { trip } = await makeTrip();
    const otherUser = await User.create({
      name: 'Other',
      phone: `+9197777${Math.floor(Math.random() * 1e5).toString().padStart(5, '0')}`,
      role: 'rider',
      passwordHash: 'unused',
    });
    const { err } = await call(tripCtrl.getDriverLocation, {
      auth: { userId: otherUser._id.toString(), role: 'rider' },
      params: { id: trip._id.toString() },
    });
    expect(err).toBeDefined();
    expect(err.status).toBe(403);
  });

  test('returns driver coords + ETA to pickup during arriving', async () => {
    const { rider, trip } = await makeTrip({ status: 'arriving' });
    const { res, err } = await call(tripCtrl.getDriverLocation, {
      auth: { userId: rider._id.toString(), role: 'rider' },
      params: { id: trip._id.toString() },
    });
    expect(err).toBeUndefined();
    expect(res.body.driver.lat).toBeCloseTo(DRIVER_POS.lat, 4);
    expect(res.body.driver.lng).toBeCloseTo(DRIVER_POS.lng, 4);
    expect(res.body.eta).toBeDefined();
    expect(res.body.eta.toStop).toBe('pickup');
    expect(res.body.eta.seconds).toBeGreaterThan(0);
    // Without GOOGLE_MAPS_KEY set, falls back to haversine.
    expect(res.body.eta.source).toBe('haversine');
  });

  test('returns ETA to dropoff during in_progress', async () => {
    const { rider, trip } = await makeTrip({ status: 'in_progress' });
    const { res } = await call(tripCtrl.getDriverLocation, {
      auth: { userId: rider._id.toString(), role: 'rider' },
      params: { id: trip._id.toString() },
    });
    expect(res.body.eta.toStop).toBe('dropoff');
  });

  test('omits ETA in non-active status (e.g. completed)', async () => {
    const { rider, trip } = await makeTrip({ status: 'completed' });
    const { res } = await call(tripCtrl.getDriverLocation, {
      auth: { userId: rider._id.toString(), role: 'rider' },
      params: { id: trip._id.toString() },
    });
    expect(res.body.eta).toBeNull();
  });
});
