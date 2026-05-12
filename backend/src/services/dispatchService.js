const Driver = require('../models/Driver');
const Trip = require('../models/Trip');
const MatchGroup = require('../models/MatchGroup');
const env = require('../config/env');
const logger = require('../utils/logger');

// =============================================================================
// Driver dispatch — offer / accept / reject flow.
//
// Old behaviour (V1): match a trip → set Driver.activeTrips → driver app
// auto-pushes to the active-trip screen. No driver agency.
//
// New behaviour: match a trip → OFFER it to the nearest driver. The driver
// has env.dispatch.offerTimeoutMs (default 15s) to accept or reject via
// /drivers/offers/:id/accept | /reject. On timeout we auto-reject and
// re-dispatch to the next-nearest driver (skipping anyone who's already
// rejected this trip).
//
// State machine (per Trip):
//
//   requested ─offerTripToDriver──► offered  ─acceptOffer──► driver_assigned
//                                      │
//                                      ├──rejectOffer──► requested (re-offer)
//                                      └──expiry timer──► requested (re-offer)
//
// In-memory timer: setTimeout fires per offer, stored in `offerTimers` so a
// process restart loses pending offers. That's a known limitation — the
// rider sees "still searching" and the trip falls back into the pool on
// the next match pass. A persistent queue (BullMQ, Cloud Tasks) is the
// follow-up when we have meaningful real-world volume.
// =============================================================================

const offerTimers = new Map(); // tripId.toString() → Timeout

// -----------------------------------------------------------------------------
// Public surface
// -----------------------------------------------------------------------------

async function offerTripToDriver(trip) {
  return _offerOne({ trip, group: null });
}

async function offerGroupToDriver(group) {
  // Late joiner: group already has an assigned driver, nothing to offer.
  if (group.driver) return null;
  return _offerOne({ trip: null, group });
}

/// Driver explicitly accepted. Commits the dispatch.
async function acceptOffer(tripId, driverId) {
  const trip = await Trip.findById(tripId);
  if (!trip) return { ok: false, reason: 'trip_not_found' };
  if (trip.status !== 'offered') return { ok: false, reason: 'not_offered' };
  if (!trip.offeredTo || trip.offeredTo.toString() !== driverId.toString()) {
    return { ok: false, reason: 'not_your_offer' };
  }

  _cancelOfferTimer(trip._id);

  // Resolve the group's full trip list if this offer was group-level.
  let tripIds = [trip._id];
  let group = null;
  if (trip.matchGroup) {
    group = await MatchGroup.findById(trip.matchGroup).populate('trips');
    if (group) {
      tripIds = group.trips.map((t) => t._id);
    }
  }

  await Driver.updateOne(
    { _id: driverId },
    { $set: { activeTrips: tripIds } },
  );

  await Trip.updateMany(
    { _id: { $in: tripIds } },
    {
      $set: {
        driver: driverId,
        status: 'driver_assigned',
      },
      $unset: {
        offeredTo: '',
        offerExpiresAt: '',
        rejectedBy: '',
      },
    },
  );

  if (group) {
    group.driver = driverId;
    if (tripIds.length >= env.match.maxRidersPerCab) {
      group.status = 'sealed';
    }
    await group.save();
  }

  logger.info(`[dispatch] accepted driver=${driverId} trips=${tripIds.length}`);
  return { ok: true, tripIds };
}

/// Driver explicitly rejected, or the offer expired. Re-dispatches.
async function rejectOffer(tripId, driverId, { reason = 'driver_rejected' } = {}) {
  const trip = await Trip.findById(tripId);
  if (!trip) return { ok: false, reason: 'trip_not_found' };
  // Idempotent: if the trip is no longer 'offered' (driver already
  // accepted on another device, or another reject already fired),
  // do nothing.
  if (trip.status !== 'offered') return { ok: false, reason: 'not_offered' };

  _cancelOfferTimer(trip._id);

  // Re-dispatch BOTH the trip and any matchGroup siblings — they were
  // all offered to the same driver.
  const memberTripIds = [];
  let group = null;
  if (trip.matchGroup) {
    group = await MatchGroup.findById(trip.matchGroup);
    if (group) memberTripIds.push(...group.trips);
  }
  if (memberTripIds.length === 0) memberTripIds.push(trip._id);

  await Trip.updateMany(
    { _id: { $in: memberTripIds } },
    {
      $set: { status: 'requested' },
      $addToSet: { rejectedBy: driverId },
      $unset: { offeredTo: '', offerExpiresAt: '' },
    },
  );

  logger.info(
    `[dispatch] ${reason} driver=${driverId} tripIds=${memberTripIds.length} — re-offering`,
  );

  // Hand back to the offer flow. If no eligible driver remains, the
  // trip(s) stay in 'requested' and the next match pass / new driver
  // coming online will pick them up.
  const fresh = await Trip.findById(trip._id).populate('matchGroup');
  if (fresh.matchGroup) {
    const freshGroup = await MatchGroup.findById(fresh.matchGroup);
    await offerGroupToDriver(freshGroup);
  } else {
    await offerTripToDriver(fresh);
  }

  return { ok: true };
}

// -----------------------------------------------------------------------------
// Internals
// -----------------------------------------------------------------------------

async function _offerOne({ trip, group }) {
  const nearPoint = group ? group.centroidPickup : trip.pickup.location;
  // Carry the rejectedBy list so we don't loop on the same driver.
  const rejectedBy = group
    ? await _groupRejectedBy(group)
    : (trip.rejectedBy || []);
  const driver = await findNearestAvailableDriver(nearPoint, {
    skipDriverIds: rejectedBy,
  });
  if (!driver) {
    logger.debug(
      `[dispatch] no driver available for ${group ? `group=${group._id}` : `trip=${trip._id}`}`,
    );
    return null;
  }

  const expiresAt = new Date(Date.now() + env.dispatch.offerTimeoutMs);

  if (group) {
    const tripIds = group.trips;
    await Trip.updateMany(
      { _id: { $in: tripIds } },
      {
        $set: {
          status: 'offered',
          offeredTo: driver._id,
          offerExpiresAt: expiresAt,
        },
      },
    );
    // Wire the expiry timer against the FIRST trip in the group — the
    // rejectOffer handler walks siblings via matchGroup.
    _scheduleExpiry(tripIds[0], driver._id);
    logger.info(
      `[dispatch] offered group=${group._id} → driver=${driver._id} expires=${expiresAt.toISOString()}`,
    );
  } else {
    trip.status = 'offered';
    trip.offeredTo = driver._id;
    trip.offerExpiresAt = expiresAt;
    await trip.save();
    _scheduleExpiry(trip._id, driver._id);
    logger.info(
      `[dispatch] offered trip=${trip._id} → driver=${driver._id} expires=${expiresAt.toISOString()}`,
    );
  }

  return driver;
}

async function _groupRejectedBy(group) {
  // Any driver who rejected ANY trip in the group is off-limits for the
  // whole group (group offers are atomic). Distinct union of rejectedBy
  // across sibling trips.
  const trips = await Trip.find({ _id: { $in: group.trips } }, { rejectedBy: 1 });
  const all = trips.flatMap((t) => t.rejectedBy || []);
  return Array.from(new Set(all.map(String))).map(
    (s) => new (require('mongoose')).Types.ObjectId(s),
  );
}

function _scheduleExpiry(tripId, driverId) {
  _cancelOfferTimer(tripId);
  const handle = setTimeout(() => {
    // Decouple the timer's stack from the async handler so an unhandled
    // throw in rejectOffer logs but doesn't poison the timer queue.
    rejectOffer(tripId, driverId, { reason: 'offer_expired' }).catch((err) => {
      logger.error(`[dispatch] expiry handler failed trip=${tripId}: ${err}`);
    });
  }, env.dispatch.offerTimeoutMs);
  offerTimers.set(tripId.toString(), handle);
}

function _cancelOfferTimer(tripId) {
  const handle = offerTimers.get(tripId.toString());
  if (handle) {
    clearTimeout(handle);
    offerTimers.delete(tripId.toString());
  }
}

async function findNearestAvailableDriver(nearPoint, { skipDriverIds = [] } = {}) {
  const skip = (skipDriverIds || []).map((id) =>
    typeof id === 'string' ? id : id.toString(),
  );

  // Pull every driver who currently has a pending offer on the wire
  // (status='offered', not yet expired). They're mid-decision on
  // another trip — offering them a second one would either get
  // silently dropped client-side (the app only renders one offer at a
  // time) or race with their accept/reject of the first. Either way
  // it's wrong. activeTrips: $size==0 already filters drivers who
  // accepted an offer; this filter covers the gap between "offered"
  // and "accepted/rejected/expired."
  const now = new Date();
  const busyWithOfferIds = await Trip.distinct('offeredTo', {
    status: 'offered',
    offerExpiresAt: { $gt: now },
    offeredTo: { $ne: null },
  });
  const nin = [...skip, ...busyWithOfferIds.map((id) => id.toString())];

  const query = {
    isOnline: true,
    activeTrips: { $size: 0 },
    currentLocation: {
      $near: {
        $geometry: nearPoint,
        $maxDistance: env.dispatch.radiusMeters,
      },
    },
  };
  if (nin.length > 0) {
    query._id = { $nin: nin };
  }
  return Driver.findOne(query);
}

module.exports = {
  // New surface
  offerTripToDriver,
  offerGroupToDriver,
  acceptOffer,
  rejectOffer,
  findNearestAvailableDriver,
  // Legacy aliases — keep callers working while we migrate them.
  // tripController.js currently calls these names; they'll point to the
  // offer flow until we update the callsites in Phase 2.
  assignDriverForTrip: offerTripToDriver,
  assignDriverForGroup: offerGroupToDriver,
};
