/**
 * Co-rider rating + skip-penalty flow.
 *
 * Validates the effective-rating math the controller documents:
 *   rating = clamp(avg(received Ratings.stars) - 0.25 * count(my skips), 1, 5)
 *
 * Each test wires call() against the rating controller's exports
 * directly — same pattern as driverDispatch.test.js — so we exercise
 * the full path including recompute, NOT a math helper in isolation.
 */

const mongoose = require('mongoose');
const { MongoMemoryServer } = require('mongodb-memory-server');

const Trip = require('../src/models/Trip');
const MatchGroup = require('../src/models/MatchGroup');
const User = require('../src/models/User');
const Rating = require('../src/models/Rating');
const RatingSkip = require('../src/models/RatingSkip');
const ratingCtrl = require('../src/controllers/ratingController');

function makeRes() {
  return {
    statusCode: 200,
    body: undefined,
    status(c) { this.statusCode = c; return this; },
    json(p) { this.body = p; return this; },
  };
}

async function call(handler, { auth, body = {}, params = {}, query = {} } = {}) {
  const req = { auth, body, params, query };
  const res = makeRes();
  let nextErr;
  await handler(req, res, (err) => { nextErr = err; });
  return { res, err: nextErr };
}

const BLR = { lat: 12.9716, lng: 77.5946 };
function pt({ lat, lng }) {
  return { type: 'Point', coordinates: [lng, lat] };
}

let mongo;
beforeAll(async () => {
  mongo = await MongoMemoryServer.create();
  await mongoose.connect(mongo.getUri());
  await Rating.init();
  await RatingSkip.init();
});
afterAll(async () => {
  await mongoose.disconnect();
  await mongo.stop();
});
beforeEach(async () => {
  await Trip.deleteMany({});
  await MatchGroup.deleteMany({});
  await User.deleteMany({});
  await Rating.deleteMany({});
  await RatingSkip.deleteMany({});
});

// Make a 2-rider matchGroup with both legs ACTUALLY completed —
// startedAt is set on each, mirroring what pickUpRider does at
// pickup time. Without startedAt the new rating gate (which guards
// against pre-pickup self-closes generating phantom rating prompts)
// rejects rate/skip with 400 + filters them out of the pending list.
async function makePairedCompletedTrip() {
  const a = await User.create({
    name: 'Rider A', phone: '+9199' + String(Math.random()).slice(2, 10),
    role: 'rider', passwordHash: 'x',
  });
  const b = await User.create({
    name: 'Rider B', phone: '+9199' + String(Math.random()).slice(2, 10),
    role: 'rider', passwordHash: 'x',
  });
  const group = await MatchGroup.create({ trips: [], status: 'completed' });
  const startedAt = new Date(Date.now() - 30 * 60 * 1000);
  const completedAt = new Date(Date.now() - 5 * 60 * 1000);
  const ta = await Trip.create({
    rider: a._id, matchGroup: group._id,
    pickup: { address: 'p', location: pt(BLR) },
    dropoff: { address: 'd', location: pt({ lat: BLR.lat + 0.05, lng: BLR.lng }) },
    status: 'completed', fareEstimate: 20000,
    startedAt, completedAt,
  });
  const tb = await Trip.create({
    rider: b._id, matchGroup: group._id,
    pickup: { address: 'p', location: pt(BLR) },
    dropoff: { address: 'd', location: pt({ lat: BLR.lat + 0.05, lng: BLR.lng }) },
    status: 'completed', fareEstimate: 20000,
    startedAt, completedAt,
  });
  group.trips = [ta._id, tb._id];
  await group.save();
  return { a, b, ta, tb, group };
}

describe('rate() — happy path', () => {
  test('records a Rating and recomputes target user rating from received avg', async () => {
    const { a, b, ta } = await makePairedCompletedTrip();
    const r = await call(ratingCtrl.rate, {
      auth: { userId: a._id.toString(), role: 'rider' },
      body: { tripId: ta._id.toString(), toUserId: b._id.toString(), stars: 3 },
    });
    expect(r.err).toBeUndefined();
    expect(r.res.body.rating.stars).toBe(3);

    const bReload = await User.findById(b._id, { rating: 1 });
    // Only one rating of 3 → avg = 3, no skips by B → effective = 3.0.
    expect(bReload.rating).toBe(3);
  });

  test('multiple ratings average correctly on the 5-star scale', async () => {
    const { a, b, ta } = await makePairedCompletedTrip();
    // Synthetic existing ratings on B.
    await Rating.create({
      trip: ta._id, fromUser: new mongoose.Types.ObjectId(), toUser: b._id, stars: 5,
    });
    await Rating.create({
      trip: ta._id, fromUser: new mongoose.Types.ObjectId(), toUser: b._id, stars: 4,
    });
    // A rates B 3 → avg of [5, 4, 3] = 4.0.
    await call(ratingCtrl.rate, {
      auth: { userId: a._id.toString(), role: 'rider' },
      body: { tripId: ta._id.toString(), toUserId: b._id.toString(), stars: 3 },
    });
    const bReload = await User.findById(b._id, { rating: 1 });
    expect(bReload.rating).toBe(4);
  });

  test('rejects rating yourself', async () => {
    const { a, ta } = await makePairedCompletedTrip();
    const r = await call(ratingCtrl.rate, {
      auth: { userId: a._id.toString(), role: 'rider' },
      body: { tripId: ta._id.toString(), toUserId: a._id.toString(), stars: 5 },
    });
    expect(r.err).toBeDefined();
    expect(r.err.status).toBe(400);
  });

  test('rejects rating someone whose leg has not completed', async () => {
    const { a, b, ta, tb } = await makePairedCompletedTrip();
    tb.status = 'in_progress';
    await tb.save();
    const r = await call(ratingCtrl.rate, {
      auth: { userId: a._id.toString(), role: 'rider' },
      body: { tripId: ta._id.toString(), toUserId: b._id.toString(), stars: 5 },
    });
    expect(r.err).toBeDefined();
    expect(r.err.status).toBe(400);
  });

  test('refuses to rate after the same pair was already skipped', async () => {
    const { a, b, ta } = await makePairedCompletedTrip();
    await RatingSkip.create({
      trip: ta._id, fromUser: a._id, toUser: b._id,
    });
    const r = await call(ratingCtrl.rate, {
      auth: { userId: a._id.toString(), role: 'rider' },
      body: { tripId: ta._id.toString(), toUserId: b._id.toString(), stars: 5 },
    });
    expect(r.err).toBeDefined();
    expect(r.err.status).toBe(409);
  });
});

describe('skipRating() — penalty math', () => {
  test('skipping applies a -0.25 penalty to the SKIPPER, not the target', async () => {
    const { a, b, ta } = await makePairedCompletedTrip();
    const beforeA = await User.findById(a._id, { rating: 1 });
    const beforeB = await User.findById(b._id, { rating: 1 });

    const r = await call(ratingCtrl.skipRating, {
      auth: { userId: a._id.toString(), role: 'rider' },
      body: { tripId: ta._id.toString(), toUserId: b._id.toString() },
    });
    expect(r.err).toBeUndefined();

    const afterA = await User.findById(a._id, { rating: 1 });
    const afterB = await User.findById(b._id, { rating: 1 });
    // A defaulted to 5, gets -0.25.
    expect(afterA.rating).toBe(beforeA.rating - 0.25);
    // B is untouched.
    expect(afterB.rating).toBe(beforeB.rating);
  });

  test('multiple skips compound: 5 → 4.75 → 4.5 → 4.25 → 4.0', async () => {
    const { a, ta } = await makePairedCompletedTrip();
    // Spin up four targets so we exercise four distinct (trip,target) skips.
    const targets = [];
    for (let i = 0; i < 4; i += 1) {
      const t = await User.create({
        name: `T${i}`,
        phone: '+9199' + String(Math.random()).slice(2, 10),
        role: 'rider', passwordHash: 'x',
      });
      // Attach as completed sibling so the eligibility check passes.
      // startedAt set — the gate filters out pre-pickup self-closes.
      const trip = await Trip.create({
        rider: t._id, matchGroup: ta.matchGroup,
        pickup: { address: 'p', location: pt(BLR) },
        dropoff: { address: 'd', location: pt({ lat: BLR.lat + 0.05, lng: BLR.lng }) },
        status: 'completed', fareEstimate: 20000,
        startedAt: new Date(Date.now() - 30 * 60 * 1000),
        completedAt: new Date(Date.now() - 5 * 60 * 1000),
      });
      const group = await MatchGroup.findById(ta.matchGroup);
      group.trips.push(trip._id);
      await group.save();
      targets.push(t);
    }

    const expectedAfter = [4.75, 4.5, 4.25, 4.0];
    for (let i = 0; i < targets.length; i += 1) {
      await call(ratingCtrl.skipRating, {
        auth: { userId: a._id.toString(), role: 'rider' },
        body: { tripId: ta._id.toString(), toUserId: targets[i]._id.toString() },
      });
      const reload = await User.findById(a._id, { rating: 1 });
      expect(reload.rating).toBeCloseTo(expectedAfter[i], 5);
    }
  });

  test('penalty floors at 1.0 even with absurd skip counts', async () => {
    // Direct test of recomputeUserRating by stuffing 20 skips.
    const u = await User.create({
      name: 'Skippy', phone: '+919000111222', role: 'rider', passwordHash: 'x',
    });
    for (let i = 0; i < 20; i += 1) {
      await RatingSkip.create({
        trip: new mongoose.Types.ObjectId(),
        fromUser: u._id,
        toUser: new mongoose.Types.ObjectId(),
      });
    }
    const result = await ratingCtrl.recomputeUserRating(u._id.toString());
    // 5 - 0.25 * 20 = 0; floored to 1.0.
    expect(result.effective).toBe(1);
    const reload = await User.findById(u._id, { rating: 1 });
    expect(reload.rating).toBe(1);
  });

  test('rating and skip combined: avg=3, 1 skip → 2.75', async () => {
    const { a, b, ta } = await makePairedCompletedTrip();
    // Someone else rates A with 3 stars.
    await Rating.create({
      trip: ta._id, fromUser: b._id, toUser: a._id, stars: 3,
    });
    // A skips rating B.
    await call(ratingCtrl.skipRating, {
      auth: { userId: a._id.toString(), role: 'rider' },
      body: { tripId: ta._id.toString(), toUserId: b._id.toString() },
    });
    const reloadA = await User.findById(a._id, { rating: 1 });
    // avg(received) = 3, skips by A = 1 → 3 - 0.25 = 2.75.
    expect(reloadA.rating).toBe(2.75);
  });

  test('refuses to skip after the pair was already rated', async () => {
    const { a, b, ta } = await makePairedCompletedTrip();
    await Rating.create({
      trip: ta._id, fromUser: a._id, toUser: b._id, stars: 4,
    });
    const r = await call(ratingCtrl.skipRating, {
      auth: { userId: a._id.toString(), role: 'rider' },
      body: { tripId: ta._id.toString(), toUserId: b._id.toString() },
    });
    expect(r.err).toBeDefined();
    expect(r.err.status).toBe(409);
  });

  test('skip is idempotent — second attempt 409s without double-penalty', async () => {
    const { a, b, ta } = await makePairedCompletedTrip();
    await call(ratingCtrl.skipRating, {
      auth: { userId: a._id.toString(), role: 'rider' },
      body: { tripId: ta._id.toString(), toUserId: b._id.toString() },
    });
    const ratingAfterFirst = (await User.findById(a._id, { rating: 1 })).rating;

    const r2 = await call(ratingCtrl.skipRating, {
      auth: { userId: a._id.toString(), role: 'rider' },
      body: { tripId: ta._id.toString(), toUserId: b._id.toString() },
    });
    expect(r2.err).toBeDefined();
    expect(r2.err.status).toBe(409);
    // Still penalised once, not twice.
    const ratingAfterSecond = (await User.findById(a._id, { rating: 1 })).rating;
    expect(ratingAfterSecond).toBe(ratingAfterFirst);
  });
});

describe('getMyPendingCoRiderRatings()', () => {
  test('lists co-riders whose leg is completed and not rated/skipped', async () => {
    const { a, b, ta } = await makePairedCompletedTrip();
    const r = await call(ratingCtrl.getMyPendingCoRiderRatings, {
      auth: { userId: a._id.toString(), role: 'rider' },
    });
    expect(r.err).toBeUndefined();
    expect(r.res.body.pending).toHaveLength(1);
    expect(r.res.body.pending[0].coRiderId).toBe(b._id.toString());
    expect(r.res.body.pending[0].tripId).toBe(ta._id.toString());
  });

  test('omits entries the user has already rated', async () => {
    const { a, b, ta } = await makePairedCompletedTrip();
    await Rating.create({
      trip: ta._id, fromUser: a._id, toUser: b._id, stars: 5,
    });
    const r = await call(ratingCtrl.getMyPendingCoRiderRatings, {
      auth: { userId: a._id.toString(), role: 'rider' },
    });
    expect(r.res.body.pending).toEqual([]);
  });

  test('omits entries the user has already skipped', async () => {
    const { a, b, ta } = await makePairedCompletedTrip();
    await RatingSkip.create({ trip: ta._id, fromUser: a._id, toUser: b._id });
    const r = await call(ratingCtrl.getMyPendingCoRiderRatings, {
      auth: { userId: a._id.toString(), role: 'rider' },
    });
    expect(r.res.body.pending).toEqual([]);
  });

  test('omits sibling trips that completed WITHOUT startedAt (pre-pickup self-close)', async () => {
    // Same setup as makePairedCompletedTrip but rider B's leg has
    // status=completed AND no startedAt — i.e. riderCloseTrip fired
    // before pickup. Riders never actually shared a cab; nothing to
    // rate. The pending list must skip this.
    const a = await User.create({
      name: 'A', phone: '+919000222111', role: 'rider', passwordHash: 'x',
    });
    const b = await User.create({
      name: 'B', phone: '+919000222112', role: 'rider', passwordHash: 'x',
    });
    const group = await MatchGroup.create({ trips: [], status: 'completed' });
    const ta = await Trip.create({
      rider: a._id, matchGroup: group._id,
      pickup: { address: 'p', location: pt(BLR) },
      dropoff: { address: 'd', location: pt({ lat: BLR.lat + 0.05, lng: BLR.lng }) },
      status: 'completed', fareEstimate: 20000,
      startedAt: new Date(),
      completedAt: new Date(),
    });
    const tb = await Trip.create({
      rider: b._id, matchGroup: group._id,
      pickup: { address: 'p', location: pt(BLR) },
      dropoff: { address: 'd', location: pt({ lat: BLR.lat + 0.05, lng: BLR.lng }) },
      // NO startedAt — this is the "rider self-closed pre-pickup" shape.
      status: 'completed', fareEstimate: 0,
      completedAt: new Date(),
    });
    group.trips = [ta._id, tb._id];
    await group.save();

    const r = await call(ratingCtrl.getMyPendingCoRiderRatings, {
      auth: { userId: a._id.toString(), role: 'rider' },
    });
    expect(r.res.body.pending).toEqual([]);
  });
});

describe('cancel penalty — recompute', () => {
  // Direct unit tests of the math. cancelTrip integration tests live
  // in driverDispatch / riderOnlyMode suites; here we exercise just
  // the rating recompute against trip cancel state, which is what
  // matters for the User.rating denormalisation.
  async function makeRider() {
    return User.create({
      name: 'R' + Math.random(),
      phone: '+9199' + String(Math.random()).slice(2, 10),
      role: 'rider', passwordHash: 'x',
    });
  }

  test('1 committed cancel: 5.0 → 4.9', async () => {
    const u = await makeRider();
    await Trip.create({
      rider: u._id,
      pickup: { address: 'p', location: pt(BLR) },
      dropoff: { address: 'd', location: pt({ lat: BLR.lat + 0.05, lng: BLR.lng }) },
      status: 'cancelled', readyToFindCab: true, fareEstimate: 0,
    });
    const r = await ratingCtrl.recomputeUserRating(u._id.toString());
    expect(r.effective).toBeCloseTo(4.9, 5);
    expect(r.cancelCount).toBe(1);
  });

  test('5 committed cancels: 5.0 → 4.5', async () => {
    const u = await makeRider();
    for (let i = 0; i < 5; i += 1) {
      await Trip.create({
        rider: u._id,
        pickup: { address: 'p', location: pt(BLR) },
        dropoff: { address: 'd', location: pt({ lat: BLR.lat + 0.05, lng: BLR.lng }) },
        status: 'cancelled', readyToFindCab: true, fareEstimate: 0,
      });
    }
    const r = await ratingCtrl.recomputeUserRating(u._id.toString());
    expect(r.effective).toBeCloseTo(4.5, 5);
  });

  test('pre-Find-Cab cancels do NOT penalise', async () => {
    const u = await makeRider();
    // Three exploratory cancels — readyToFindCab=false on all.
    for (let i = 0; i < 3; i += 1) {
      await Trip.create({
        rider: u._id,
        pickup: { address: 'p', location: pt(BLR) },
        dropoff: { address: 'd', location: pt({ lat: BLR.lat + 0.05, lng: BLR.lng }) },
        status: 'cancelled', readyToFindCab: false, fareEstimate: 0,
      });
    }
    const r = await ratingCtrl.recomputeUserRating(u._id.toString());
    expect(r.effective).toBe(5);
    expect(r.cancelCount).toBe(0);
  });

  test('combined: 1 skip + 2 cancels + avg 3 = 3 - 0.25 - 0.2 = 2.55', async () => {
    const u = await makeRider();
    const co = await makeRider();
    // 1 received Rating of 3 → avg=3
    await Rating.create({
      trip: new mongoose.Types.ObjectId(), fromUser: co._id, toUser: u._id, stars: 3,
    });
    // 1 skip
    await RatingSkip.create({
      trip: new mongoose.Types.ObjectId(), fromUser: u._id, toUser: co._id,
    });
    // 2 committed cancels
    for (let i = 0; i < 2; i += 1) {
      await Trip.create({
        rider: u._id,
        pickup: { address: 'p', location: pt(BLR) },
        dropoff: { address: 'd', location: pt({ lat: BLR.lat + 0.05, lng: BLR.lng }) },
        status: 'cancelled', readyToFindCab: true, fareEstimate: 0,
      });
    }
    const r = await ratingCtrl.recomputeUserRating(u._id.toString());
    // 3 - 0.25*1 - 0.10*2 = 3 - 0.25 - 0.20 = 2.55
    expect(r.effective).toBeCloseTo(2.55, 5);
  });

  test('cancel penalty floors at 1.0', async () => {
    const u = await makeRider();
    // 50 committed cancels → 5 - 5 = 0 → floor 1.0
    for (let i = 0; i < 50; i += 1) {
      await Trip.create({
        rider: u._id,
        pickup: { address: 'p', location: pt(BLR) },
        dropoff: { address: 'd', location: pt({ lat: BLR.lat + 0.05, lng: BLR.lng }) },
        status: 'cancelled', readyToFindCab: true, fareEstimate: 0,
      });
    }
    const r = await ratingCtrl.recomputeUserRating(u._id.toString());
    expect(r.effective).toBe(1);
  });
});
