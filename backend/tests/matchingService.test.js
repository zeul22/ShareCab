const mongoose = require('mongoose');
const { MongoMemoryServer } = require('mongodb-memory-server');

const { findMatchForTrip } = require('../src/services/matchingService');
const Trip = require('../src/models/Trip');
const MatchGroup = require('../src/models/MatchGroup');
const env = require('../src/config/env');

// Bengaluru anchor — keeps test coordinates intuitive.
const BLR = { lat: 12.9716, lng: 77.5946 };

// Approximate degree offset for ~1 km at Bengaluru's latitude.
const KM_LAT = 0.009;
const KM_LNG = 0.0092;

function pt({ lat, lng }) {
  return { type: 'Point', coordinates: [lng, lat] };
}

function offset(base, km, axis = 'lat') {
  return axis === 'lat'
    ? { lat: base.lat + km * KM_LAT, lng: base.lng }
    : { lat: base.lat, lng: base.lng + km * KM_LNG };
}

async function makeTrip({ pickup, dropoff, status = 'requested', shareEnabled = true }) {
  return Trip.create({
    rider: new mongoose.Types.ObjectId(),
    pickup: { address: 'p', location: pt(pickup) },
    dropoff: { address: 'd', location: pt(dropoff) },
    shareEnabled,
    status,
  });
}

let mongo;

beforeAll(async () => {
  mongo = await MongoMemoryServer.create();
  await mongoose.connect(mongo.getUri());
  // 2dsphere indexes are required for $near queries used in matching.
  await Trip.init();
  await MatchGroup.init();
});

afterAll(async () => {
  await mongoose.disconnect();
  await mongo.stop();
});

beforeEach(async () => {
  await Trip.deleteMany({});
  await MatchGroup.deleteMany({});
});

describe('findMatchForTrip — guard rails', () => {
  test('returns null when trip does not exist', async () => {
    const ghost = new mongoose.Types.ObjectId();
    expect(await findMatchForTrip(ghost)).toBeNull();
  });

  test('returns null when shareEnabled is false', async () => {
    const drop = offset(BLR, 5);
    const t = await makeTrip({ pickup: BLR, dropoff: drop, shareEnabled: false });
    expect(await findMatchForTrip(t._id)).toBeNull();
    expect(await MatchGroup.countDocuments()).toBe(0);
  });

  test('returns null when trip is no longer in `requested` status', async () => {
    const drop = offset(BLR, 5);
    const t = await makeTrip({ pickup: BLR, dropoff: drop, status: 'in_progress' });
    expect(await findMatchForTrip(t._id)).toBeNull();
  });
});

describe('findMatchForTrip — pairing two solo trips', () => {
  test('forms a group when pickup and drop are both within radius', async () => {
    const drop = offset(BLR, 5);
    const a = await makeTrip({ pickup: BLR, dropoff: drop });
    const b = await makeTrip({
      pickup: offset(BLR, 1),                  // ~1 km away — under 2 km pickup radius
      dropoff: offset(drop, 1),                // ~1 km away — under 4 km drop radius
    });

    const group = await findMatchForTrip(b._id);
    expect(group).not.toBeNull();
    expect(group.status).toBe('forming');
    expect(group.trips.map(String).sort()).toEqual([a._id, b._id].map(String).sort());

    const [aFresh, bFresh] = await Promise.all([Trip.findById(a._id), Trip.findById(b._id)]);
    expect(aFresh.status).toBe('matched');
    expect(bFresh.status).toBe('matched');
    expect(String(aFresh.matchGroup)).toBe(String(group._id));
    expect(String(bFresh.matchGroup)).toBe(String(group._id));
  });

  test('does NOT pair when pickups are farther than the pickup radius', async () => {
    const drop = offset(BLR, 5);
    await makeTrip({ pickup: BLR, dropoff: drop });
    const farPickup = offset(BLR, env.match.pickupRadiusKm + 1.5); // outside radius
    const b = await makeTrip({ pickup: farPickup, dropoff: offset(drop, 0.5) });

    expect(await findMatchForTrip(b._id)).toBeNull();
    expect(await MatchGroup.countDocuments()).toBe(0);
  });

  test('does NOT pair when drops are farther than the destination radius', async () => {
    const drop = offset(BLR, 5);
    await makeTrip({ pickup: BLR, dropoff: drop });
    const farDrop = offset(drop, env.match.destinationRadiusKm + 2); // outside radius
    const b = await makeTrip({ pickup: offset(BLR, 0.5), dropoff: farDrop });

    expect(await findMatchForTrip(b._id)).toBeNull();
    expect(await MatchGroup.countDocuments()).toBe(0);
  });

  test('skips trips that already belong to a match group', async () => {
    const drop = offset(BLR, 5);
    await makeTrip({
      pickup: BLR,
      dropoff: drop,
      // already grouped — must not be picked up by the solo-pair search
    }).then((t) =>
      Trip.updateOne({ _id: t._id }, { matchGroup: new mongoose.Types.ObjectId() }),
    );
    const b = await makeTrip({ pickup: offset(BLR, 0.5), dropoff: offset(drop, 0.5) });

    expect(await findMatchForTrip(b._id)).toBeNull();
    expect(await MatchGroup.countDocuments()).toBe(0);
  });
});

describe('findMatchForTrip — joining an existing group', () => {
  test('a third compatible trip joins and seals the group at maxRidersPerCab', async () => {
    const drop = offset(BLR, 5);
    const a = await makeTrip({ pickup: BLR, dropoff: drop });
    const b = await makeTrip({ pickup: offset(BLR, 0.4), dropoff: offset(drop, 0.4) });

    const formed = await findMatchForTrip(b._id);
    expect(formed.status).toBe('forming');

    const c = await makeTrip({ pickup: offset(BLR, 0.7), dropoff: offset(drop, 0.6) });
    const joined = await findMatchForTrip(c._id);

    expect(String(joined._id)).toBe(String(formed._id));
    expect(joined.trips).toHaveLength(env.match.maxRidersPerCab);
    expect(joined.status).toBe('sealed'); // 3 riders ⇒ sealed

    const cFresh = await Trip.findById(c._id);
    expect(cFresh.status).toBe('matched');
    expect(String(cFresh.matchGroup)).toBe(String(formed._id));

    // Sanity: the trip array contains all three.
    expect(joined.trips.map(String).sort())
      .toEqual([a._id, b._id, c._id].map(String).sort());
  });

  test('does not join a group whose centroid drop is too far', async () => {
    const drop = offset(BLR, 5);
    const a = await makeTrip({ pickup: BLR, dropoff: drop });
    const b = await makeTrip({ pickup: offset(BLR, 0.4), dropoff: offset(drop, 0.4) });
    const formed = await findMatchForTrip(b._id);
    expect(formed).not.toBeNull();

    // Same pickup zone, but drop wildly off
    const farDrop = offset(drop, env.match.destinationRadiusKm + 3);
    const c = await makeTrip({ pickup: offset(BLR, 0.5), dropoff: farDrop });

    expect(await findMatchForTrip(c._id)).toBeNull();

    const groupAfter = await MatchGroup.findById(formed._id);
    expect(groupAfter.trips).toHaveLength(2); // unchanged
  });

  test('a sealed group is not considered for new joiners', async () => {
    const drop = offset(BLR, 5);
    // pre-seed a sealed group
    const sealed = await MatchGroup.create({
      trips: [new mongoose.Types.ObjectId(), new mongoose.Types.ObjectId()],
      status: 'sealed',
      centroidPickup: pt(BLR),
      centroidDropoff: pt(drop),
    });

    const t = await makeTrip({ pickup: offset(BLR, 0.3), dropoff: offset(drop, 0.3) });
    const result = await findMatchForTrip(t._id);

    // No solo partners exist either → null
    expect(result).toBeNull();
    const sealedAfter = await MatchGroup.findById(sealed._id);
    expect(sealedAfter.trips).toHaveLength(2);
  });
});
