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

describe('pickUpRider OTP gate', () => {
  // Pickup now requires the rider's 4-digit OTP. Trips created via
  // requestTrip carry an OTP; trips created via Trip.create here have
  // to set it explicitly. The gate is no-op when trip.otp is falsy
  // (transitional path for legacy data).
  test('rejects with 400 when no OTP supplied and trip has an OTP', async () => {
    const { user, driver } = await makeDriverWithUser();
    const { trip } = await makeRiderTrip({ driver, status: 'arriving' });
    trip.otp = '4242';
    await trip.save();
    const auth = { userId: user._id.toString(), role: 'driver' };

    const r = await call(tripCtrl.pickUpRider, {
      auth,
      params: { id: trip._id.toString() },
      body: {},
    });
    expect(r.err).toBeDefined();
    expect(r.err.status).toBe(400);
    expect((await Trip.findById(trip._id)).status).toBe('arriving');
  });

  test('rejects with 400 when wrong OTP supplied', async () => {
    const { user, driver } = await makeDriverWithUser();
    const { trip } = await makeRiderTrip({ driver, status: 'arriving' });
    trip.otp = '4242';
    await trip.save();
    const auth = { userId: user._id.toString(), role: 'driver' };

    const r = await call(tripCtrl.pickUpRider, {
      auth,
      params: { id: trip._id.toString() },
      body: { otp: '1111' },
    });
    expect(r.err).toBeDefined();
    expect(r.err.status).toBe(400);
    expect(r.err.message).toMatch(/wrong otp/i);
  });

  test('advances to in_progress when correct OTP supplied', async () => {
    const { user, driver } = await makeDriverWithUser();
    const { trip } = await makeRiderTrip({ driver, status: 'arriving' });
    trip.otp = '4242';
    await trip.save();
    driver.activeTrips = [trip._id];
    await driver.save();
    const auth = { userId: user._id.toString(), role: 'driver' };

    const r = await call(tripCtrl.pickUpRider, {
      auth,
      params: { id: trip._id.toString() },
      body: { otp: '4242' },
    });
    expect(r.err).toBeUndefined();
    expect((await Trip.findById(trip._id)).status).toBe('in_progress');
  });

  test('legacy trips without an OTP still pick up (no gate enforced)', async () => {
    // Trips created before the OTP rollout (Trip.otp == null) keep
    // working — the gate is opt-in based on whether the trip carries
    // an OTP. Once `requestTrip` has been issuing OTPs long enough
    // that no legacy trips remain, the fallback can be tightened.
    const { user, driver } = await makeDriverWithUser();
    const { trip } = await makeRiderTrip({ driver, status: 'arriving' });
    expect(trip.otp).toBeUndefined();
    const auth = { userId: user._id.toString(), role: 'driver' };

    const r = await call(tripCtrl.pickUpRider, {
      auth,
      params: { id: trip._id.toString() },
      body: {},
    });
    expect(r.err).toBeUndefined();
    expect((await Trip.findById(trip._id)).status).toBe('in_progress');
  });
});

describe('findCab — both-rider consent gate', () => {
  // Solo trips bypass the gate entirely (readyToFindCab is set true at
  // trip creation). Shared trips only dispatch once every member has
  // tapped Find Cab.
  test('rejects with 409 when called on a non-matched trip', async () => {
    const rider = await User.create({
      name: 'Rider', phone: '+919000000001', role: 'rider', passwordHash: 'x',
    });
    const trip = await Trip.create({
      rider: rider._id,
      pickup: { address: 'p', location: pt(BLR) },
      dropoff: { address: 'd', location: pt({ lat: BLR.lat + 0.05, lng: BLR.lng + 0.05 }) },
      status: 'requested',
      fareEstimate: 200,
    });
    const r = await call(tripCtrl.findCab, {
      auth: { userId: rider._id.toString(), role: 'rider' },
      params: { id: trip._id.toString() },
    });
    expect(r.err).toBeDefined();
    expect(r.err.status).toBe(409);
  });

  test('first rider sets readyToFindCab=true; no dispatch yet', async () => {
    const r1 = await User.create({
      name: 'R1', phone: '+919000000002', role: 'rider', passwordHash: 'x',
    });
    const r2 = await User.create({
      name: 'R2', phone: '+919000000003', role: 'rider', passwordHash: 'x',
    });
    const group = await MatchGroup.create({ trips: [], status: 'forming' });
    const trip1 = await Trip.create({
      rider: r1._id, matchGroup: group._id,
      pickup: { address: 'p', location: pt(BLR) },
      dropoff: { address: 'd', location: pt({ lat: BLR.lat + 0.05, lng: BLR.lng + 0.05 }) },
      status: 'matched', fareEstimate: 200,
    });
    const trip2 = await Trip.create({
      rider: r2._id, matchGroup: group._id,
      pickup: { address: 'p', location: pt(BLR) },
      dropoff: { address: 'd', location: pt({ lat: BLR.lat + 0.05, lng: BLR.lng + 0.05 }) },
      status: 'matched', fareEstimate: 200,
    });
    group.trips = [trip1._id, trip2._id];
    await group.save();

    const r = await call(tripCtrl.findCab, {
      auth: { userId: r1._id.toString(), role: 'rider' },
      params: { id: trip1._id.toString() },
    });
    expect(r.err).toBeUndefined();
    // Only rider 1 is ready; sibling stays at false. Status remains
    // matched (no dispatch happened) — there's no online driver in
    // the test env anyway, but the key invariant is that the trip
    // didn't go to 'offered'.
    expect((await Trip.findById(trip1._id)).readyToFindCab).toBe(true);
    expect((await Trip.findById(trip2._id)).readyToFindCab).toBe(false);
    expect((await Trip.findById(trip1._id)).status).toBe('matched');
    expect((await Trip.findById(trip2._id)).status).toBe('matched');
  });

  test('second rider closes the gate; both ready triggers dispatch (no driver found stays matched)', async () => {
    // With no online driver in the test, the dispatch service's
    // findNearestAvailableDriver returns null and the trips stay
    // matched. We assert the gate fired by checking both readyToFindCab
    // bits are true.
    const r1 = await User.create({
      name: 'R1', phone: '+919000000004', role: 'rider', passwordHash: 'x',
    });
    const r2 = await User.create({
      name: 'R2', phone: '+919000000005', role: 'rider', passwordHash: 'x',
    });
    const group = await MatchGroup.create({ trips: [], status: 'forming' });
    const trip1 = await Trip.create({
      rider: r1._id, matchGroup: group._id,
      pickup: { address: 'p', location: pt(BLR) },
      dropoff: { address: 'd', location: pt({ lat: BLR.lat + 0.05, lng: BLR.lng + 0.05 }) },
      status: 'matched', readyToFindCab: true, fareEstimate: 200,
    });
    const trip2 = await Trip.create({
      rider: r2._id, matchGroup: group._id,
      pickup: { address: 'p', location: pt(BLR) },
      dropoff: { address: 'd', location: pt({ lat: BLR.lat + 0.05, lng: BLR.lng + 0.05 }) },
      status: 'matched', fareEstimate: 200,
    });
    group.trips = [trip1._id, trip2._id];
    await group.save();

    const r = await call(tripCtrl.findCab, {
      auth: { userId: r2._id.toString(), role: 'rider' },
      params: { id: trip2._id.toString() },
    });
    expect(r.err).toBeUndefined();
    expect((await Trip.findById(trip2._id)).readyToFindCab).toBe(true);
  });

  test('rejects when caller is not the trip rider', async () => {
    const r1 = await User.create({
      name: 'R1', phone: '+919000000006', role: 'rider', passwordHash: 'x',
    });
    const intruder = await User.create({
      name: 'Other', phone: '+919000000007', role: 'rider', passwordHash: 'x',
    });
    const trip = await Trip.create({
      rider: r1._id,
      pickup: { address: 'p', location: pt(BLR) },
      dropoff: { address: 'd', location: pt({ lat: BLR.lat + 0.05, lng: BLR.lng + 0.05 }) },
      status: 'matched', fareEstimate: 200,
    });
    const r = await call(tripCtrl.findCab, {
      auth: { userId: intruder._id.toString(), role: 'rider' },
      params: { id: trip._id.toString() },
    });
    expect(r.err).toBeDefined();
    expect(r.err.status).toBe(403);
  });
});
