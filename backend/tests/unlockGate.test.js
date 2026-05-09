const mongoose = require('mongoose');
const { MongoMemoryServer } = require('mongodb-memory-server');

const Unlock = require('../src/models/Unlock');

// These tests cover the atomic-consume query that gates `requestTrip` —
// see tripController.requestTrip's `Unlock.findOneAndUpdate(...)`. We test
// the query directly so the contract (single-use, expiry, rider isolation,
// soonest-expiry-first) is locked in without needing an HTTP harness.

let mongo;

beforeAll(async () => {
  mongo = await MongoMemoryServer.create();
  await mongoose.connect(mongo.getUri());
  await Unlock.init();
});

afterAll(async () => {
  await mongoose.disconnect();
  await mongo.stop();
});

beforeEach(async () => {
  await Unlock.deleteMany({});
});

const RIDER = new mongoose.Types.ObjectId();
const OTHER_RIDER = new mongoose.Types.ObjectId();

function consume(riderId, now = new Date()) {
  return Unlock.findOneAndUpdate(
    { rider: riderId, usedAt: null, expiresAt: { $gt: now } },
    { $set: { usedAt: now } },
    { sort: { expiresAt: 1 } },
  );
}

async function makeUnlock({ rider = RIDER, source = 'ad', expiresInMs = 60_000, usedAt = null } = {}) {
  return Unlock.create({
    rider,
    source,
    expiresAt: new Date(Date.now() + expiresInMs),
    usedAt,
  });
}

describe('unlock gate — atomic consume', () => {
  test('fresh unlock can be consumed once', async () => {
    const u = await makeUnlock();

    const consumed = await consume(RIDER);
    expect(consumed).not.toBeNull();
    expect(consumed._id.toString()).toBe(u._id.toString());

    const reload = await Unlock.findById(u._id);
    expect(reload.usedAt).not.toBeNull();
  });

  test('consumed unlock cannot be consumed again (single-use)', async () => {
    await makeUnlock();
    const first = await consume(RIDER);
    expect(first).not.toBeNull();

    const second = await consume(RIDER);
    expect(second).toBeNull();
  });

  test('expired unlock is invisible to the consume query', async () => {
    await makeUnlock({ expiresInMs: -1000 }); // already expired
    const consumed = await consume(RIDER);
    expect(consumed).toBeNull();
  });

  test('a rider cannot consume another rider\'s unlock', async () => {
    await makeUnlock({ rider: OTHER_RIDER });
    const consumed = await consume(RIDER);
    expect(consumed).toBeNull();

    // The other rider's unlock is still untouched.
    const others = await Unlock.find({ rider: OTHER_RIDER });
    expect(others).toHaveLength(1);
    expect(others[0].usedAt).toBeNull();
  });

  test('with multiple unlocks, the soonest-to-expire is consumed first', async () => {
    const later = await makeUnlock({ expiresInMs: 60_000 });
    const sooner = await makeUnlock({ expiresInMs: 10_000 });

    const consumed = await consume(RIDER);
    expect(consumed._id.toString()).toBe(sooner._id.toString());

    const laterFresh = await Unlock.findById(later._id);
    expect(laterFresh.usedAt).toBeNull();
  });

  test('concurrent consume attempts only succeed once', async () => {
    await makeUnlock();
    const [a, b, c] = await Promise.all([consume(RIDER), consume(RIDER), consume(RIDER)]);
    const winners = [a, b, c].filter(Boolean);
    expect(winners).toHaveLength(1);
  });
});

describe('unlock gate — payment vs ad source', () => {
  test('both sources yield consumable unlocks; source is preserved', async () => {
    await makeUnlock({ source: 'ad' });
    const adConsumed = await consume(RIDER);
    expect(adConsumed.source).toBe('ad');

    await makeUnlock({ source: 'payment' });
    const payConsumed = await consume(RIDER);
    expect(payConsumed.source).toBe('payment');
  });
});
