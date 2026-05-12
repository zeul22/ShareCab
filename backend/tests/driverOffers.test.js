/**
 * Driver offer / accept / reject lifecycle.
 *
 * Asserts the new Uber-style flow:
 *   - offerTripToDriver puts the trip in 'offered' state with offeredTo set
 *   - acceptOffer transitions to 'driver_assigned' + populates activeTrips
 *   - rejectOffer puts the trip back to 'requested' AND re-offers to the
 *     next-nearest driver, skipping the one who rejected
 *   - the offer-expiry timer fires auto-reject after env.dispatch.offerTimeoutMs
 *
 * Uses an in-memory Mongo (consistent with existing test style) and calls
 * dispatchService + driverController directly with mocked req/res.
 */

const mongoose = require('mongoose');
const { MongoMemoryServer } = require('mongodb-memory-server');

const Trip = require('../src/models/Trip');
const Driver = require('../src/models/Driver');
const User = require('../src/models/User');
const env = require('../src/config/env');
const dispatchService = require('../src/services/dispatchService');
const driverCtrl = require('../src/controllers/driverController');

const BLR = { lat: 12.9716, lng: 77.5946 };
function pt({ lat, lng }) { return { type: 'Point', coordinates: [lng, lat] }; }
function makeRes() {
  return {
    statusCode: 200, body: undefined,
    status(c) { this.statusCode = c; return this; },
    json(p) { this.body = p; return this; },
    set() { return this; },
    end() { this.body = undefined; return this; },
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
let origTimeoutMs;
beforeAll(async () => {
  mongo = await MongoMemoryServer.create();
  await mongoose.connect(mongo.getUri());
  // findNearestAvailableDriver runs a $near query against the 2dsphere
  // index on Driver.currentLocation. Without an explicit init the index
  // is created lazily on first write, which races the first $near query
  // and intermittently fails the suite with "unable to find index for
  // $geoNear query." Force the build up-front.
  await Driver.init();
  // Shorten the offer timeout for tests so expiry assertions don't wait 30s.
  origTimeoutMs = env.dispatch.offerTimeoutMs;
  env.dispatch.offerTimeoutMs = 200;
});
afterAll(async () => {
  // Drain any in-flight offer-expiry timers before tearing down Mongo —
  // otherwise a fire-after-disconnect logs a "MongoNotConnectedError"
  // from the background timer that's harmless but loud.
  await new Promise((r) => setTimeout(r, env.dispatch.offerTimeoutMs + 250));
  env.dispatch.offerTimeoutMs = origTimeoutMs;
  await mongoose.disconnect();
  await mongo.stop();
});
beforeEach(async () => {
  await Trip.deleteMany({});
  await Driver.deleteMany({});
  await User.deleteMany({});
});

// Build a driver near a point. `offset` lets us spread multiple drivers
// in a deterministic order — driver 1 nearest, driver 2 a bit further, etc.
async function makeOnlineDriver({ offset = 0 } = {}) {
  const user = await User.create({
    name: `Driver ${offset}`,
    phone: `+91999${String(Math.random()).slice(2, 10)}`,
    role: 'driver',
    passwordHash: 'x',
  });
  return Driver.create({
    user: user._id,
    licenseNumber: `KA01-${offset}`,
    vehicle: { model: 'Dzire', plate: `KA0${offset}1234`, color: 'White', capacity: 4 },
    isOnline: true,
    activeTrips: [],
    currentLocation: pt({ lat: BLR.lat + offset * 0.001, lng: BLR.lng }),
    subscriptionStartedAt: new Date(),
    subscriptionExpiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
    subscriptionPaymentRef: 'free-trial',
  });
}

async function makeRequestedTrip() {
  const rider = await User.create({
    name: 'Rider',
    phone: `+9198${String(Math.random()).slice(2, 10)}`,
    role: 'rider',
    passwordHash: 'x',
  });
  return Trip.create({
    rider: rider._id,
    pickup: { address: 'BLR', location: pt(BLR) },
    dropoff: {
      address: 'Drop',
      location: pt({ lat: BLR.lat + 0.05, lng: BLR.lng + 0.05 }),
    },
    status: 'requested',
    fareEstimate: 15000,
  });
}

describe('dispatchService.offerTripToDriver', () => {
  test('puts trip in offered state and sets offeredTo + offerExpiresAt', async () => {
    const d = await makeOnlineDriver({ offset: 1 });
    const trip = await makeRequestedTrip();

    const offered = await dispatchService.offerTripToDriver(trip);
    expect(offered._id.toString()).toBe(d._id.toString());

    const reloaded = await Trip.findById(trip._id);
    expect(reloaded.status).toBe('offered');
    expect(reloaded.offeredTo.toString()).toBe(d._id.toString());
    expect(reloaded.offerExpiresAt).toBeInstanceOf(Date);
    expect(reloaded.offerExpiresAt.getTime()).toBeGreaterThan(Date.now());
    // Driver is NOT committed yet — activeTrips stays empty until accept.
    const dReloaded = await Driver.findById(d._id);
    expect(dReloaded.activeTrips).toEqual([]);
  });

  test('returns null when no online driver is in range', async () => {
    const trip = await makeRequestedTrip();
    const offered = await dispatchService.offerTripToDriver(trip);
    expect(offered).toBeNull();
  });

  test('skips a driver who already has a pending offer on the wire', async () => {
    // Two online drivers, one (the nearest) already mid-decision on
    // another trip. The second trip's dispatch should pick the
    // farther driver, not pile a competing offer on the busy one.
    const d1 = await makeOnlineDriver({ offset: 1 }); // nearest
    const d2 = await makeOnlineDriver({ offset: 5 }); // farther
    const first = await makeRequestedTrip();
    const second = await makeRequestedTrip();

    const o1 = await dispatchService.offerTripToDriver(first);
    expect(o1._id.toString()).toBe(d1._id.toString());

    // d1 is now in `offered`. Dispatch the second trip — must skip d1.
    const o2 = await dispatchService.offerTripToDriver(second);
    expect(o2).not.toBeNull();
    expect(o2._id.toString()).toBe(d2._id.toString());
  });

  test('drivers in an active trip are still excluded (regression)', async () => {
    // activeTrips: { $size: 0 } was the original filter — keep it
    // pinned alongside the new offered-trip filter so we don't
    // accidentally remove either when refactoring.
    const d1 = await makeOnlineDriver({ offset: 1 });
    const d2 = await makeOnlineDriver({ offset: 5 });
    // Pretend d1 already accepted a trip somewhere.
    d1.activeTrips = [new mongoose.Types.ObjectId()];
    await d1.save();

    const trip = await makeRequestedTrip();
    const offered = await dispatchService.offerTripToDriver(trip);
    expect(offered).not.toBeNull();
    expect(offered._id.toString()).toBe(d2._id.toString());
  });
});

describe('dispatchService.acceptOffer', () => {
  test('happy path: status → driver_assigned, activeTrips populated, offer fields cleared', async () => {
    const d = await makeOnlineDriver({ offset: 1 });
    const trip = await makeRequestedTrip();
    await dispatchService.offerTripToDriver(trip);

    const res = await dispatchService.acceptOffer(trip._id, d._id);
    expect(res.ok).toBe(true);

    const reloaded = await Trip.findById(trip._id);
    expect(reloaded.status).toBe('driver_assigned');
    expect(reloaded.driver.toString()).toBe(d._id.toString());
    expect(reloaded.offeredTo).toBeNull();
    expect(reloaded.offerExpiresAt).toBeNull();

    const dReloaded = await Driver.findById(d._id);
    expect(dReloaded.activeTrips.map(String)).toContain(trip._id.toString());
  });

  test('rejects when offer no longer matches this driver', async () => {
    const d1 = await makeOnlineDriver({ offset: 1 });
    const d2 = await makeOnlineDriver({ offset: 2 });
    const trip = await makeRequestedTrip();
    await dispatchService.offerTripToDriver(trip); // offered to d1 (nearest)

    const res = await dispatchService.acceptOffer(trip._id, d2._id);
    expect(res.ok).toBe(false);
    expect(res.reason).toBe('not_your_offer');
  });
});

describe('dispatchService.rejectOffer', () => {
  test('reject → trip re-offered to the next-nearest driver, skipping rejector', async () => {
    const d1 = await makeOnlineDriver({ offset: 1 });
    const d2 = await makeOnlineDriver({ offset: 2 });
    const trip = await makeRequestedTrip();
    await dispatchService.offerTripToDriver(trip);

    // Confirm d1 was offered.
    let reloaded = await Trip.findById(trip._id);
    expect(reloaded.offeredTo.toString()).toBe(d1._id.toString());

    await dispatchService.rejectOffer(trip._id, d1._id);

    reloaded = await Trip.findById(trip._id);
    // After reject, the trip was re-offered to d2 (next-nearest).
    expect(reloaded.status).toBe('offered');
    expect(reloaded.offeredTo.toString()).toBe(d2._id.toString());
    expect(reloaded.rejectedBy.map(String)).toContain(d1._id.toString());
  });

  test('reject when no eligible driver remains leaves trip in requested state', async () => {
    const d1 = await makeOnlineDriver({ offset: 1 });
    const trip = await makeRequestedTrip();
    await dispatchService.offerTripToDriver(trip);

    await dispatchService.rejectOffer(trip._id, d1._id);

    const reloaded = await Trip.findById(trip._id);
    expect(reloaded.status).toBe('requested');
    expect(reloaded.offeredTo).toBeNull();
    expect(reloaded.rejectedBy.map(String)).toContain(d1._id.toString());
  });
});

describe('offer expiry timer', () => {
  test('auto-rejects after offerTimeoutMs', async () => {
    const d = await makeOnlineDriver({ offset: 1 });
    const trip = await makeRequestedTrip();
    await dispatchService.offerTripToDriver(trip);

    // Wait past the (shortened, 200ms) timeout + a small buffer.
    await new Promise((r) => setTimeout(r, 350));

    const reloaded = await Trip.findById(trip._id);
    // No second driver in range → re-offer fails → trip parked in 'requested'.
    expect(reloaded.status).toBe('requested');
    expect(reloaded.rejectedBy.map(String)).toContain(d._id.toString());
  });
});

describe('driverController.getMyOffer', () => {
  test('204 when no offer is pending', async () => {
    const d = await makeOnlineDriver({ offset: 1 });
    const { res } = await call(driverCtrl.getMyOffer, {
      auth: { userId: d.user.toString(), role: 'driver' },
    });
    expect(res.statusCode).toBe(204);
  });

  test('returns the offered trip when one is pending', async () => {
    const d = await makeOnlineDriver({ offset: 1 });
    const trip = await makeRequestedTrip();
    await dispatchService.offerTripToDriver(trip);

    const { res } = await call(driverCtrl.getMyOffer, {
      auth: { userId: d.user.toString(), role: 'driver' },
    });
    expect(res.body).toBeDefined();
    expect(res.body.offer._id.toString()).toBe(trip._id.toString());
    expect(res.body.offer.status).toBe('offered');
  });
});

describe('driverController.acceptOffer + rejectOffer', () => {
  test('accept controller wires through to dispatchService', async () => {
    const d = await makeOnlineDriver({ offset: 1 });
    const trip = await makeRequestedTrip();
    await dispatchService.offerTripToDriver(trip);

    const { res, err } = await call(driverCtrl.acceptOffer, {
      auth: { userId: d.user.toString(), role: 'driver' },
      params: { tripId: trip._id.toString() },
    });
    expect(err).toBeUndefined();
    expect(res.body.ok).toBe(true);

    const reloaded = await Trip.findById(trip._id);
    expect(reloaded.status).toBe('driver_assigned');
  });

  test('reject controller returns 204', async () => {
    const d = await makeOnlineDriver({ offset: 1 });
    const trip = await makeRequestedTrip();
    await dispatchService.offerTripToDriver(trip);

    const { res, err } = await call(driverCtrl.rejectOffer, {
      auth: { userId: d.user.toString(), role: 'driver' },
      params: { tripId: trip._id.toString() },
    });
    expect(err).toBeUndefined();
    expect(res.statusCode).toBe(204);
  });
});
