/**
 * MATCH_RIDER_ONLY mode. Behaviour-pinning tests for the no-drivers-yet
 * launch configuration: matching engine still pairs riders, but no
 * driver dispatch happens and the unlock gate moves from
 * trip-creation to /trips/:id/unlock-match.
 *
 * We don't reload modules between tests — env is a single cached object
 * so we flip env.match.riderOnly directly. Beats the require-cache
 * dance and matches the pattern used elsewhere in this suite.
 */

const mongoose = require('mongoose');
const { MongoMemoryServer } = require('mongodb-memory-server');

const tripCtrl = require('../src/controllers/tripController');
const Trip = require('../src/models/Trip');
const Driver = require('../src/models/Driver');
const User = require('../src/models/User');
const Unlock = require('../src/models/Unlock');
const MatchGroup = require('../src/models/MatchGroup');
const env = require('../src/config/env');

function makeRes() {
  return {
    statusCode: 200,
    body: undefined,
    status(c) { this.statusCode = c; return this; },
    json(p) { this.body = p; return this; },
  };
}

async function call(handler, { auth, body = {}, params = {}, query = {} }) {
  const req = { auth, body, params, query };
  const res = makeRes();
  let nextErr;
  await handler(req, res, (err) => { nextErr = err; });
  return { res, err: nextErr };
}

// Bengaluru anchor + 1km-apart helper.
const BLR = { lat: 12.9716, lng: 77.5946 };
function nudgeKm(km) {
  return { lat: BLR.lat + km * 0.009, lng: BLR.lng };
}

let mongo;
let originalRiderOnly;

beforeAll(async () => {
  mongo = await MongoMemoryServer.create();
  await mongoose.connect(mongo.getUri());
  originalRiderOnly = env.match.riderOnly;
  // 2dsphere indexes are required for the $near queries the matching
  // engine performs. Without these, findMatchForTrip returns null.
  await Trip.init();
  await MatchGroup.init();
  await Driver.init();
});

afterAll(async () => {
  env.match.riderOnly = originalRiderOnly;
  await mongoose.disconnect();
  await mongo.stop();
});

beforeEach(async () => {
  await Trip.deleteMany({});
  await Driver.deleteMany({});
  await User.deleteMany({});
  await Unlock.deleteMany({});
  await MatchGroup.deleteMany({});
});

async function makeRider() {
  return User.create({
    name: `Rider ${Math.random().toString(36).slice(2, 6)}`,
    phone: `+9199${Math.floor(Math.random() * 1e8).toString().padStart(8, '0')}`,
    role: 'rider',
    passwordHash: 'unused',
  });
}

async function giveUnlock(rider, source = 'ad') {
  return Unlock.create({
    rider: rider._id,
    source,
    usedAt: null,
    expiresAt: new Date(Date.now() + 60 * 60 * 1000),
  });
}

function tripBody({ pickup, drop, shareEnabled = true }) {
  return {
    pickup: { address: 'pickup', ...pickup },
    dropoff: { address: 'drop', ...drop },
    shareEnabled,
  };
}

describe('requestTrip in rider-only mode', () => {
  beforeEach(() => { env.match.riderOnly = true; });

  test('creates the trip without consuming an unlock', async () => {
    const rider = await makeRider();
    // Deliberately do NOT give them an unlock.
    const r = await call(tripCtrl.requestTrip, {
      auth: { userId: rider._id.toString(), role: 'rider' },
      body: tripBody({ pickup: BLR, drop: nudgeKm(4) }),
    });
    expect(r.err).toBeUndefined();
    expect(await Trip.countDocuments({ rider: rider._id })).toBe(1);
    // Unlock was never minted, so none should be consumed.
    expect(await Unlock.countDocuments({ usedAt: { $ne: null } })).toBe(0);
  });

  test('pairs two riders into a match group, no driver assigned', async () => {
    const a = await makeRider();
    const b = await makeRider();

    await call(tripCtrl.requestTrip, {
      auth: { userId: a._id.toString(), role: 'rider' },
      body: tripBody({ pickup: BLR, drop: nudgeKm(5) }),
    });
    await call(tripCtrl.requestTrip, {
      auth: { userId: b._id.toString(), role: 'rider' },
      // Pickup very close + drop within destination radius (4km default)
      body: tripBody({ pickup: nudgeKm(0.5), drop: nudgeKm(5) }),
    });

    const trips = await Trip.find().sort({ createdAt: 1 });
    expect(trips).toHaveLength(2);
    // Both should belong to one match group; both should be 'matched'.
    expect(trips[0].matchGroup).toBeDefined();
    expect(trips[1].matchGroup).toBeDefined();
    expect(String(trips[0].matchGroup)).toBe(String(trips[1].matchGroup));
    expect(trips.every((t) => t.status === 'matched')).toBe(true);
    // And no driver was assigned to either.
    expect(trips.every((t) => t.driver == null)).toBe(true);
  });

  test('solo (shareEnabled=false) trip is auto-cancelled', async () => {
    const rider = await makeRider();
    const r = await call(tripCtrl.requestTrip, {
      auth: { userId: rider._id.toString(), role: 'rider' },
      body: tripBody({ pickup: BLR, drop: nudgeKm(5), shareEnabled: false }),
    });
    expect(r.err).toBeUndefined();
    const trip = await Trip.findOne({ rider: rider._id });
    expect(trip.status).toBe('cancelled');
    expect(trip.cancelReason).toContain('rider-only');
  });
});

describe('unlockMatch endpoint', () => {
  beforeEach(() => { env.match.riderOnly = true; });

  async function makeMatchedPair() {
    const a = await makeRider();
    const b = await makeRider();
    await call(tripCtrl.requestTrip, {
      auth: { userId: a._id.toString(), role: 'rider' },
      body: tripBody({ pickup: BLR, drop: nudgeKm(5) }),
    });
    await call(tripCtrl.requestTrip, {
      auth: { userId: b._id.toString(), role: 'rider' },
      body: tripBody({ pickup: nudgeKm(0.5), drop: nudgeKm(5) }),
    });
    const trips = await Trip.find().sort({ createdAt: 1 });
    return { a, b, tripA: trips[0], tripB: trips[1] };
  }

  test('consumes one unlock and sets matchRevealedAt', async () => {
    const { a, tripA } = await makeMatchedPair();
    const unlock = await giveUnlock(a);
    const r = await call(tripCtrl.unlockMatch, {
      auth: { userId: a._id.toString(), role: 'rider' },
      params: { id: tripA._id.toString() },
    });
    expect(r.err).toBeUndefined();
    const after = await Trip.findById(tripA._id);
    expect(after.matchRevealedAt).toBeInstanceOf(Date);
    const usedUnlock = await Unlock.findById(unlock._id);
    expect(usedUnlock.usedAt).not.toBeNull();
    expect(String(usedUnlock.usedForTrip)).toBe(String(tripA._id));
  });

  test('402 when rider has no usable unlock', async () => {
    const { a, tripA } = await makeMatchedPair();
    const r = await call(tripCtrl.unlockMatch, {
      auth: { userId: a._id.toString(), role: 'rider' },
      params: { id: tripA._id.toString() },
    });
    expect(r.err).toBeDefined();
    expect(r.err.status).toBe(402);
  });

  test('idempotent on a second call (no double-spend)', async () => {
    const { a, tripA } = await makeMatchedPair();
    await giveUnlock(a);
    await call(tripCtrl.unlockMatch, {
      auth: { userId: a._id.toString(), role: 'rider' },
      params: { id: tripA._id.toString() },
    });
    // Issue a second unlock — if the endpoint isn't idempotent it'd
    // consume this one too.
    const second = await giveUnlock(a);
    const r2 = await call(tripCtrl.unlockMatch, {
      auth: { userId: a._id.toString(), role: 'rider' },
      params: { id: tripA._id.toString() },
    });
    expect(r2.err).toBeUndefined();
    expect(r2.res.body.alreadyUnlocked).toBe(true);
    const secondAfter = await Unlock.findById(second._id);
    expect(secondAfter.usedAt).toBeNull();
  });

  test('409 when no match has formed yet', async () => {
    const rider = await makeRider();
    await giveUnlock(rider);
    const r1 = await call(tripCtrl.requestTrip, {
      auth: { userId: rider._id.toString(), role: 'rider' },
      body: tripBody({ pickup: BLR, drop: nudgeKm(4) }),
    });
    expect(r1.err).toBeUndefined();
    const trip = await Trip.findOne({ rider: rider._id });
    const r2 = await call(tripCtrl.unlockMatch, {
      auth: { userId: rider._id.toString(), role: 'rider' },
      params: { id: trip._id.toString() },
    });
    expect(r2.err).toBeDefined();
    expect(r2.err.status).toBe(409);
  });

  test('403 when a different rider tries to unlock', async () => {
    const { tripA } = await makeMatchedPair();
    const stranger = await makeRider();
    await giveUnlock(stranger);
    const r = await call(tripCtrl.unlockMatch, {
      auth: { userId: stranger._id.toString(), role: 'rider' },
      params: { id: tripA._id.toString() },
    });
    expect(r.err).toBeDefined();
    expect(r.err.status).toBe(403);
  });
});

describe('getTrip redaction in rider-only mode', () => {
  beforeEach(() => { env.match.riderOnly = true; });

  async function setupMatchedPair() {
    const a = await makeRider();
    const b = await makeRider();
    await call(tripCtrl.requestTrip, {
      auth: { userId: a._id.toString(), role: 'rider' },
      body: tripBody({ pickup: BLR, drop: nudgeKm(5) }),
    });
    await call(tripCtrl.requestTrip, {
      auth: { userId: b._id.toString(), role: 'rider' },
      body: tripBody({ pickup: nudgeKm(0.5), drop: nudgeKm(5) }),
    });
    const trips = await Trip.find().sort({ createdAt: 1 });
    return { a, b, tripA: trips[0], tripB: trips[1] };
  }

  test('co-rider details are hidden before unlock', async () => {
    const { a, tripA } = await setupMatchedPair();
    const r = await call(tripCtrl.getTrip, {
      auth: { userId: a._id.toString(), role: 'rider' },
      params: { id: tripA._id.toString() },
    });
    expect(r.err).toBeUndefined();
    const group = r.res.body.trip.matchGroup;
    expect(group.trips).toHaveLength(2);
    // My own trip stays detailed.
    const mine = group.trips.find((t) => String(t._id) === String(tripA._id));
    expect(mine.pickup).toBeDefined();
    // Co-rider's trip is redacted.
    const sibling = group.trips.find((t) => String(t._id) !== String(tripA._id));
    expect(sibling.redacted).toBe(true);
    expect(sibling.pickup).toBeUndefined();
    expect(sibling.rider).toBeUndefined();
  });

  test('co-rider details revealed after unlock', async () => {
    const { a, tripA } = await setupMatchedPair();
    await giveUnlock(a);
    await call(tripCtrl.unlockMatch, {
      auth: { userId: a._id.toString(), role: 'rider' },
      params: { id: tripA._id.toString() },
    });
    const r = await call(tripCtrl.getTrip, {
      auth: { userId: a._id.toString(), role: 'rider' },
      params: { id: tripA._id.toString() },
    });
    expect(r.err).toBeUndefined();
    const group = r.res.body.trip.matchGroup;
    const sibling = group.trips.find((t) => String(t._id) !== String(tripA._id));
    expect(sibling.redacted).toBeUndefined();
    expect(sibling.pickup).toBeDefined();
    expect(sibling.rider).toEqual(expect.objectContaining({
      name: expect.any(String),
    }));
  });
});

describe('riderCloseTrip — self-completion in rider-only mode', () => {
  beforeEach(() => { env.match.riderOnly = true; });

  async function setupMatchedPair() {
    const a = await makeRider();
    const b = await makeRider();
    await call(tripCtrl.requestTrip, {
      auth: { userId: a._id.toString(), role: 'rider' },
      body: tripBody({ pickup: BLR, drop: nudgeKm(5) }),
    });
    await call(tripCtrl.requestTrip, {
      auth: { userId: b._id.toString(), role: 'rider' },
      body: tripBody({ pickup: nudgeKm(0.5), drop: nudgeKm(5) }),
    });
    const trips = await Trip.find().sort({ createdAt: 1 });
    return { a, b, tripA: trips[0], tripB: trips[1] };
  }

  test('marks the trip completed with fareFinal=0', async () => {
    const { a, tripA } = await setupMatchedPair();
    const r = await call(tripCtrl.riderCloseTrip, {
      auth: { userId: a._id.toString(), role: 'rider' },
      params: { id: tripA._id.toString() },
    });
    expect(r.err).toBeUndefined();
    const after = await Trip.findById(tripA._id);
    expect(after.status).toBe('completed');
    expect(after.fareFinal).toBe(0);
    expect(after.completedAt).toBeInstanceOf(Date);
  });

  test('sets startedAt so the rating gate fires', async () => {
    // Regression: rider-only closes used to leave startedAt null,
    // which silently filtered the trip out of the co-rider rating
    // pending list (the gate is `startedAt != null` — meant to
    // exclude pre-pickup self-closes in driver-dispatch mode).
    // Now riderCloseTrip stamps startedAt at close time when nothing
    // else set it, so the rating prompt actually appears.
    const { a, tripA } = await setupMatchedPair();
    expect(tripA.startedAt).toBeFalsy();
    await call(tripCtrl.riderCloseTrip, {
      auth: { userId: a._id.toString(), role: 'rider' },
      params: { id: tripA._id.toString() },
    });
    const after = await Trip.findById(tripA._id);
    expect(after.startedAt).toBeInstanceOf(Date);
  });

  test('idempotent: closing a closed trip returns alreadyClosed', async () => {
    const { a, tripA } = await setupMatchedPair();
    await call(tripCtrl.riderCloseTrip, {
      auth: { userId: a._id.toString(), role: 'rider' },
      params: { id: tripA._id.toString() },
    });
    const r2 = await call(tripCtrl.riderCloseTrip, {
      auth: { userId: a._id.toString(), role: 'rider' },
      params: { id: tripA._id.toString() },
    });
    expect(r2.err).toBeUndefined();
    expect(r2.res.body.alreadyClosed).toBe(true);
  });

  test('group settles only when last sibling closes', async () => {
    const { a, b, tripA, tripB } = await setupMatchedPair();
    await call(tripCtrl.riderCloseTrip, {
      auth: { userId: a._id.toString(), role: 'rider' },
      params: { id: tripA._id.toString() },
    });
    // Group is NOT yet completed — b hasn't closed.
    const group1 = await MatchGroup.findById(
      (await Trip.findById(tripA._id)).matchGroup,
    );
    expect(group1.status).not.toBe('completed');
    // Close b → group flips.
    await call(tripCtrl.riderCloseTrip, {
      auth: { userId: b._id.toString(), role: 'rider' },
      params: { id: tripB._id.toString() },
    });
    const group2 = await MatchGroup.findById(group1._id);
    expect(group2.status).toBe('completed');
  });

  test('403 when another rider tries to close someone else\'s trip', async () => {
    const { tripA } = await setupMatchedPair();
    const stranger = await makeRider();
    const r = await call(tripCtrl.riderCloseTrip, {
      auth: { userId: stranger._id.toString(), role: 'rider' },
      params: { id: tripA._id.toString() },
    });
    expect(r.err).toBeDefined();
    expect(r.err.status).toBe(403);
  });

  test('409 when trip status is "requested" (no match yet)', async () => {
    const rider = await makeRider();
    await call(tripCtrl.requestTrip, {
      auth: { userId: rider._id.toString(), role: 'rider' },
      body: tripBody({ pickup: BLR, drop: nudgeKm(4) }),
    });
    const trip = await Trip.findOne({ rider: rider._id });
    const r = await call(tripCtrl.riderCloseTrip, {
      auth: { userId: rider._id.toString(), role: 'rider' },
      params: { id: trip._id.toString() },
    });
    expect(r.err).toBeDefined();
    expect(r.err.status).toBe(409);
  });
});

describe('riderCloseTrip in driver-dispatch mode', () => {
  beforeEach(() => { env.match.riderOnly = false; });

  test('rejects with 409 when a driver is assigned', async () => {
    // Per-trip gating — a trip *with* a driver belongs on /end-early
    // so the driver still gets paid. The env flag is irrelevant; what
    // matters is whether this specific trip has a driver attached.
    const rider = await makeRider();
    await giveUnlock(rider);
    await call(tripCtrl.requestTrip, {
      auth: { userId: rider._id.toString(), role: 'rider' },
      body: tripBody({ pickup: BLR, drop: nudgeKm(4) }),
    });
    const trip = await Trip.findOne({ rider: rider._id });
    // Force-attach a driver so the gate trips. Using a synthetic ObjectId
    // is enough — the controller only checks for truthiness.
    trip.driver = new mongoose.Types.ObjectId();
    await trip.save();
    const r = await call(tripCtrl.riderCloseTrip, {
      auth: { userId: rider._id.toString(), role: 'rider' },
      params: { id: trip._id.toString() },
    });
    expect(r.err).toBeDefined();
    expect(r.err.status).toBe(409);
    expect(r.err.message).toContain('/end-early');
  });

  test('succeeds when no driver is assigned (rider arranged off-platform)', async () => {
    // Trip matched with a co-rider but no driver dispatched yet — e.g.
    // dispatch hadn't found anyone, or the rider gave up waiting and
    // arranged transport elsewhere. Closing should still work, fare=0.
    // Previously this hit the env-flag gate and 409'd unconditionally.
    const rider = await makeRider();
    await giveUnlock(rider);
    await call(tripCtrl.requestTrip, {
      auth: { userId: rider._id.toString(), role: 'rider' },
      body: tripBody({ pickup: BLR, drop: nudgeKm(4) }),
    });
    const trip = await Trip.findOne({ rider: rider._id });
    // Force into a closable status without attaching a driver — mirrors
    // a matched-but-undispatched trip in driver-dispatch mode.
    trip.status = 'matched';
    await trip.save();
    expect(trip.driver).toBeFalsy();
    const r = await call(tripCtrl.riderCloseTrip, {
      auth: { userId: rider._id.toString(), role: 'rider' },
      params: { id: trip._id.toString() },
    });
    expect(r.err).toBeUndefined();
    const reloaded = await Trip.findById(trip._id);
    expect(reloaded.status).toBe('completed');
    expect(reloaded.fareFinal).toBe(0);
  });
});

describe('driver-dispatch mode unaffected', () => {
  // Sanity check that rider-only mode is purely opt-in and the old
  // path still works when the flag is false. (The full driver-side
  // suite is in driverDispatch.test.js — this is just a smoke check.)
  beforeEach(() => { env.match.riderOnly = false; });

  // Trip creation no longer requires an upfront unlock in either mode.
  // The unlock gate moved to /trips/:id/unlock-match (post-match) so
  // we don't charge the rider before they actually have a co-rider to
  // share with. Both ad and pay paths still gate behind that endpoint;
  // see unlockGate.test.js for the consume mechanics.
  test('requestTrip with shareEnabled succeeds without upfront unlock', async () => {
    const rider = await makeRider();
    const r = await call(tripCtrl.requestTrip, {
      auth: { userId: rider._id.toString(), role: 'rider' },
      body: tripBody({ pickup: BLR, drop: nudgeKm(4) }),
    });
    expect(r.err).toBeUndefined();
    expect(r.res.body.trip).toBeDefined();
    expect(r.res.body.trip.status).toBe('requested');
  });
});
