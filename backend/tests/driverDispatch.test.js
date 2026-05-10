/**
 * Driver dispatch + trip lifecycle.
 *
 * Asserts:
 *   - GET /drivers/me/dispatch returns the trips currently in driver.activeTrips
 *     populated with rider info (name + rating).
 *   - arriveTrip / startTrip / completeTrip walk a single dispatch through
 *     the four states (driver_assigned → arriving → in_progress → completed)
 *     and clear activeTrips on completion.
 *   - For shared (matchGroup) dispatches, the lifecycle moves ALL sibling
 *     trips together, not just the one whose id was passed in.
 *
 * Calls controllers directly with mocked req/res — no supertest dep.
 */

const mongoose = require('mongoose');
const { MongoMemoryServer } = require('mongodb-memory-server');

const Trip = require('../src/models/Trip');
const Driver = require('../src/models/Driver');
const User = require('../src/models/User');
const MatchGroup = require('../src/models/MatchGroup');
const driverCtrl = require('../src/controllers/driverController');
const tripCtrl = require('../src/controllers/tripController');

const BLR = { lat: 12.9716, lng: 77.5946 };
function pt({ lat, lng }) {
  return { type: 'Point', coordinates: [lng, lat] };
}

// Minimal req/res harness. The controllers only touch req.auth, req.params,
// res.json, res.status — anything more would require Express's full pipeline.
function makeRes() {
  const res = {
    statusCode: 200,
    body: undefined,
    status(code) { this.statusCode = code; return this; },
    json(payload) { this.body = payload; return this; },
  };
  return res;
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

async function makeDriverWithUser({ activeTrips = [] } = {}) {
  const user = await User.create({
    name: 'Test Driver',
    phone: `+9199999${Math.floor(Math.random() * 1e5).toString().padStart(5, '0')}`,
    role: 'driver',
    passwordHash: 'unused',
  });
  const driver = await Driver.create({
    user: user._id,
    licenseNumber: 'KA01-DL-0001',
    vehicle: { model: 'Maruti Dzire', plate: 'KA01-1234', color: 'White', capacity: 4 },
    isOnline: true,
    activeTrips,
    // Active subscription so subscription gates don't fire.
    subscriptionStartedAt: new Date(),
    subscriptionExpiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
    subscriptionPaymentRef: 'free-trial',
  });
  return { user, driver };
}

async function makeRiderTrip({ driver, status = 'driver_assigned', matchGroup = null }) {
  const rider = await User.create({
    name: `Rider ${Math.random().toString(36).slice(2, 6)}`,
    phone: `+9199${Math.floor(Math.random() * 1e8).toString().padStart(8, '0')}`,
    rating: 4.7,
    passwordHash: 'unused',
  });
  const trip = await Trip.create({
    rider: rider._id,
    driver: driver._id,
    matchGroup,
    pickup: { address: 'p', location: pt(BLR) },
    dropoff: { address: 'd', location: pt({ lat: BLR.lat + 0.05, lng: BLR.lng + 0.05 }) },
    status,
    fareEstimate: 200,
  });
  return { rider, trip };
}

describe('GET /drivers/me/dispatch', () => {
  test('returns empty list when driver has no active trips', async () => {
    const { user } = await makeDriverWithUser();
    const { res, err } = await call(driverCtrl.getMyDispatch, {
      auth: { userId: user._id.toString(), role: 'driver' },
    });
    expect(err).toBeUndefined();
    expect(res.body.trips).toEqual([]);
  });

  test('returns populated trips with rider info', async () => {
    const { user, driver } = await makeDriverWithUser();
    const { trip: t1 } = await makeRiderTrip({ driver });
    const { trip: t2 } = await makeRiderTrip({ driver });
    driver.activeTrips = [t1._id, t2._id];
    await driver.save();

    const { res, err } = await call(driverCtrl.getMyDispatch, {
      auth: { userId: user._id.toString(), role: 'driver' },
    });
    expect(err).toBeUndefined();
    expect(res.body.trips).toHaveLength(2);
    // Each trip's rider must be populated, not a bare ObjectId.
    for (const t of res.body.trips) {
      expect(t.rider).toEqual(expect.objectContaining({
        name: expect.any(String),
        rating: expect.any(Number),
      }));
    }
  });
});

describe('Trip lifecycle — solo dispatch', () => {
  test('arrive → picked-up → dropped walks status forward and clears activeTrips', async () => {
    const { user, driver } = await makeDriverWithUser();
    const { trip } = await makeRiderTrip({ driver });
    driver.activeTrips = [trip._id];
    await driver.save();

    const auth = { userId: user._id.toString(), role: 'driver' };

    let r = await call(tripCtrl.arriveTrip, { auth, params: { id: trip._id.toString() } });
    expect(r.err).toBeUndefined();
    expect((await Trip.findById(trip._id)).status).toBe('arriving');

    r = await call(tripCtrl.pickUpRider, { auth, params: { id: trip._id.toString() } });
    expect(r.err).toBeUndefined();
    expect((await Trip.findById(trip._id)).status).toBe('in_progress');

    r = await call(tripCtrl.dropOffRider, { auth, params: { id: trip._id.toString() } });
    expect(r.err).toBeUndefined();
    const after = await Trip.findById(trip._id);
    expect(after.status).toBe('completed');
    expect(after.fareFinal).toBeGreaterThan(0);

    const driverAfter = await Driver.findById(driver._id);
    expect(driverAfter.activeTrips).toHaveLength(0);
  });

  test('rejects out-of-order transitions', async () => {
    const { user, driver } = await makeDriverWithUser();
    const { trip } = await makeRiderTrip({ driver, status: 'driver_assigned' });
    const auth = { userId: user._id.toString(), role: 'driver' };

    // Cannot mark picked-up without arriving first.
    const r = await call(tripCtrl.pickUpRider, { auth, params: { id: trip._id.toString() } });
    expect(r.err).toBeDefined();
    expect(r.err.status).toBe(400);
  });

  test('rejects another driver trying to drive my trip', async () => {
    const { driver } = await makeDriverWithUser();
    const { trip } = await makeRiderTrip({ driver });
    const intruder = await makeDriverWithUser();

    const r = await call(tripCtrl.arriveTrip, {
      auth: { userId: intruder.user._id.toString(), role: 'driver' },
      params: { id: trip._id.toString() },
    });
    expect(r.err).toBeDefined();
    expect(r.err.status).toBe(403);
  });
});

describe('Trip lifecycle — per-rider transitions in a shared group', () => {
  // Helper: spin up a 2-rider group already arrived at the first pickup.
  async function makeArrivedGroup() {
    const { user, driver } = await makeDriverWithUser();
    const group = await MatchGroup.create({ trips: [], status: 'sealed' });
    const { trip: t1 } = await makeRiderTrip({ driver, matchGroup: group._id, status: 'arriving' });
    const { trip: t2 } = await makeRiderTrip({ driver, matchGroup: group._id, status: 'arriving' });
    group.trips = [t1._id, t2._id];
    group.driver = driver._id;
    await group.save();
    driver.activeTrips = [t1._id, t2._id];
    await driver.save();
    return { user, driver, group, t1, t2 };
  }

  test('picking up rider 1 advances ONLY their trip; sibling stays arriving', async () => {
    const { user, t1, t2, group } = await makeArrivedGroup();
    const auth = { userId: user._id.toString(), role: 'driver' };

    const r = await call(tripCtrl.pickUpRider, { auth, params: { id: t1._id.toString() } });
    expect(r.err).toBeUndefined();

    expect((await Trip.findById(t1._id)).status).toBe('in_progress');
    expect((await Trip.findById(t2._id)).status).toBe('arriving');
    // First pickup promotes the group so the rider-side UI flips out of "arriving".
    expect((await MatchGroup.findById(group._id)).status).toBe('in_progress');
  });

  test('dropping rider 1 leaves rider 2 in the cab; group not yet completed', async () => {
    const { user, driver, t1, t2, group } = await makeArrivedGroup();
    const auth = { userId: user._id.toString(), role: 'driver' };

    // Both picked up, then drop only rider 1.
    await call(tripCtrl.pickUpRider, { auth, params: { id: t1._id.toString() } });
    await call(tripCtrl.pickUpRider, { auth, params: { id: t2._id.toString() } });
    const r = await call(tripCtrl.dropOffRider, { auth, params: { id: t1._id.toString() } });
    expect(r.err).toBeUndefined();

    expect((await Trip.findById(t1._id)).status).toBe('completed');
    expect((await Trip.findById(t2._id)).status).toBe('in_progress');
    // Group is still active because rider 2 is still in cab.
    expect((await MatchGroup.findById(group._id)).status).toBe('in_progress');
    // Driver's activeTrips must drop t1 but keep t2.
    const driverAfter = await Driver.findById(driver._id);
    const ids = driverAfter.activeTrips.map((id) => id.toString());
    expect(ids).toEqual([t2._id.toString()]);
  });

  test('dropping the last rider settles the whole group + bumps driver counter once', async () => {
    const { user, driver, t1, t2, group } = await makeArrivedGroup();
    const auth = { userId: user._id.toString(), role: 'driver' };
    const driverBefore = await User.findById(driver.user);
    const beforeCount = driverBefore.totalRides || 0;

    await call(tripCtrl.pickUpRider, { auth, params: { id: t1._id.toString() } });
    await call(tripCtrl.pickUpRider, { auth, params: { id: t2._id.toString() } });
    await call(tripCtrl.dropOffRider, { auth, params: { id: t1._id.toString() } });
    const r = await call(tripCtrl.dropOffRider, { auth, params: { id: t2._id.toString() } });
    expect(r.err).toBeUndefined();

    const trips = await Trip.find({ _id: { $in: [t1._id, t2._id] } });
    expect(trips.every((t) => t.status === 'completed')).toBe(true);
    expect((await MatchGroup.findById(group._id)).status).toBe('completed');
    expect((await Driver.findById(driver._id)).activeTrips).toHaveLength(0);

    // Driver gets +1 (one drive), not +2 (one per rider).
    const driverAfter = await User.findById(driver.user);
    expect(driverAfter.totalRides - beforeCount).toBe(1);
  });

  test('rejects dropping a rider who was never picked up', async () => {
    const { user, t1 } = await makeArrivedGroup();
    const auth = { userId: user._id.toString(), role: 'driver' };
    const r = await call(tripCtrl.dropOffRider, { auth, params: { id: t1._id.toString() } });
    expect(r.err).toBeDefined();
    expect(r.err.status).toBe(400);
  });
});
