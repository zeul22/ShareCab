const mongoose = require('mongoose');
const { z } = require('zod');
const Rating = require('../models/Rating');
const RatingSkip = require('../models/RatingSkip');
const Trip = require('../models/Trip');
const MatchGroup = require('../models/MatchGroup');
const User = require('../models/User');
const { HttpError } = require('../middleware/errorHandler');

// =============================================================================
// Rating engine.
//
// Three signals feed a user's `User.rating` (denormalised effective score):
//   - Rating       — stars(1-5) someone gave them on a completed trip.
//   - RatingSkip   — they declined to rate a co-rider, -0.25 each.
//   - cancel       — they committed to a trip (readyToFindCab=true) and
//                    then cancelled it, -0.1 each. Counted by querying
//                    Trip directly (the trip doc already has all the
//                    state we need; no separate collection).
//
// Effective rating formula (validated against the 5-star scale):
//
//   avg     = average of stars in incoming Ratings,  default 5 when none
//   skips   = count of outgoing RatingSkips
//   cancels = count of own Trips where status='cancelled' AND
//             readyToFindCab=true
//   rating  = clamp(avg - 0.25 * skips - 0.10 * cancels,  min 1, max 5)
//
// Hand-math sanity check:
//   - New rider, no activity:               avg=5, skips=0, cancels=0   → 5.0
//   - Skips one rating prompt:               avg=5, skips=1              → 4.75
//   - Cancels one committed trip:            avg=5, cancels=1            → 4.9
//   - Cancels 5 committed trips:             avg=5, cancels=5            → 4.5
//   - Cancels 5 + skips 1:                   avg=5, cancels=5, skips=1   → 4.25
//   - Rated 3★ + skipped once + 2 cancels:   avg=3, skips=1, cancels=2   → 2.55
//   - 50 cancels (pathological):             avg=5, cancels=50           → floor at 1.0
//
// Recompute fires on any of: new Rating against a user (they're the
// target), new RatingSkip from a user (they're the skipper), or
// trip cancellation by a user who'd already tapped Find Cab.
// =============================================================================

const SKIP_PENALTY = 0.25;
const CANCEL_PENALTY = 0.10;

async function recomputeUserRating(userId) {
  const objectId = new mongoose.Types.ObjectId(userId);
  const [agg, skipCount, cancelCount] = await Promise.all([
    Rating.aggregate([
      { $match: { toUser: objectId } },
      { $group: { _id: '$toUser', avg: { $avg: '$stars' }, count: { $sum: 1 } } },
    ]),
    RatingSkip.countDocuments({ fromUser: objectId }),
    // Committed-then-cancelled: the rider tapped Find Cab (or it was
    // implicit on a solo trip created with shareEnabled=false, in
    // which case readyToFindCab is set at trip-create time too)
    // before bailing. Pre-Find-Cab cancellations don't count — those
    // are exploratory and the driver supply hadn't been touched.
    Trip.countDocuments({
      rider: objectId,
      status: 'cancelled',
      readyToFindCab: true,
    }),
  ]);
  const baseAvg = agg[0]?.avg ?? 5;
  const raw = baseAvg - SKIP_PENALTY * skipCount - CANCEL_PENALTY * cancelCount;
  const effective = Math.max(1, Math.min(5, raw));
  await User.findByIdAndUpdate(userId, { $set: { rating: effective } });
  return {
    effective,
    baseAvg,
    skipCount,
    cancelCount,
    ratingCount: agg[0]?.count ?? 0,
  };
}

// -----------------------------------------------------------------------------
// POST /api/ratings — used to rate the driver AND each co-rider on a
// shared trip. The unique index on (trip, fromUser, toUser) means each
// (rater, ratee) pair gets one row per trip; trying to re-rate the
// same pair surfaces as 409.
// -----------------------------------------------------------------------------

const rateSchema = z.object({
  tripId: z.string(),
  toUserId: z.string(),
  stars: z.number().int().min(1).max(5),
  comment: z.string().max(500).optional(),
});

async function rate(req, res, next) {
  try {
    const parsed = rateSchema.safeParse(req.body);
    if (!parsed.success) {
      throw new HttpError(400, 'Invalid rating payload: needs { tripId, toUserId, stars: 1-5 }');
    }
    const data = parsed.data;

    const trip = await Trip.findById(data.tripId);
    if (!trip) throw new HttpError(404, 'Trip not found');

    // Co-rider rating only requires the trip the OTHER party is on to
    // be completed — they've left the cab, the leg is settled. The
    // requesting rider's own leg can still be in_progress (they'll
    // get to rate from inside the cab between drops).
    const targetLeg = await _legForUser(trip, data.toUserId);
    if (!targetLeg) throw new HttpError(404, 'Co-rider not in this trip');
    if (!_isLegRateable(targetLeg)) {
      throw new HttpError(400, 'Can only rate a co-rider once their ride has actually started + ended');
    }
    // The rater can't rate themselves.
    if (req.auth.userId === data.toUserId) {
      throw new HttpError(400, 'Cannot rate yourself');
    }

    // Refuse if the rater already skipped this pair — they have to
    // pick one decision per (trip, target). Avoids letting a skip
    // penalty be retroactively cleared by a rating.
    const alreadySkipped = await RatingSkip.findOne({
      trip: trip._id,
      fromUser: req.auth.userId,
      toUser: data.toUserId,
    }, { _id: 1 });
    if (alreadySkipped) {
      throw new HttpError(409, 'You already skipped rating this co-rider; cannot rate now');
    }

    const rating = await Rating.create({
      trip: trip._id,
      fromUser: req.auth.userId,
      toUser: data.toUserId,
      stars: data.stars,
      comment: data.comment,
    });

    const result = await recomputeUserRating(data.toUserId);
    res.status(201).json({ rating, target: result });
  } catch (err) {
    if (err.code === 11000) return next(new HttpError(409, 'Already rated this pair on this trip'));
    next(err);
  }
}

// -----------------------------------------------------------------------------
// POST /api/ratings/skip — rider explicitly declined to rate a co-rider.
// Applies a -0.25 penalty to the SKIPPER (not the would-be ratee).
// -----------------------------------------------------------------------------

const skipSchema = z.object({
  tripId: z.string(),
  toUserId: z.string(),
});

async function skipRating(req, res, next) {
  try {
    const parsed = skipSchema.safeParse(req.body);
    if (!parsed.success) {
      throw new HttpError(400, 'Invalid skip payload: needs { tripId, toUserId }');
    }
    const data = parsed.data;

    const trip = await Trip.findById(data.tripId);
    if (!trip) throw new HttpError(404, 'Trip not found');

    const targetLeg = await _legForUser(trip, data.toUserId);
    if (!targetLeg) throw new HttpError(404, 'Co-rider not in this trip');
    if (!_isLegRateable(targetLeg)) {
      throw new HttpError(400, 'Can only skip a co-rider once their ride has actually started + ended');
    }
    if (req.auth.userId === data.toUserId) {
      throw new HttpError(400, 'Cannot skip yourself');
    }

    // Refuse if a real Rating already exists for this pair — they
    // can't undo it by skipping afterwards.
    const alreadyRated = await Rating.findOne({
      trip: trip._id,
      fromUser: req.auth.userId,
      toUser: data.toUserId,
    }, { _id: 1 });
    if (alreadyRated) {
      throw new HttpError(409, 'You already rated this co-rider; cannot skip now');
    }

    try {
      await RatingSkip.create({
        trip: trip._id,
        fromUser: req.auth.userId,
        toUser: data.toUserId,
      });
    } catch (err) {
      if (err.code === 11000) {
        throw new HttpError(409, 'Already skipped this co-rider on this trip');
      }
      throw err;
    }

    // Recompute the SKIPPER's effective rating — they're the one
    // taking the penalty, not the co-rider they refused to rate.
    const result = await recomputeUserRating(req.auth.userId);
    res.status(201).json({
      skipped: true,
      penalty: 0.25,
      myRating: result,
    });
  } catch (err) {
    next(err);
  }
}

// -----------------------------------------------------------------------------
// GET /api/ratings/pending — co-riders this user owes a decision on.
//
// A pending entry exists when, on a trip where the user was a rider,
// some OTHER rider's leg has completed AND this user has neither
// rated nor skipped them yet. Used by the rider app to know who to
// prompt for after a sibling-completion poll tick.
// -----------------------------------------------------------------------------

async function getMyPendingCoRiderRatings(req, res, next) {
  try {
    const userId = req.auth.userId;
    const userObjId = new mongoose.Types.ObjectId(userId);

    // Look back 7 days — anything older and we stop bugging the user.
    const since = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
    const myTrips = await Trip.find(
      { rider: userObjId, createdAt: { $gt: since }, matchGroup: { $ne: null } },
      { _id: 1, matchGroup: 1 },
    );
    if (myTrips.length === 0) return res.json({ pending: [] });

    const groupIds = myTrips.map((t) => t.matchGroup);
    const myTripIds = myTrips.map((t) => t._id);

    // All sibling trips in those groups that have actually FINISHED
    // a started ride (status=completed AND startedAt is set), excluding
    // the user's own legs. The startedAt gate matters: trips can flip
    // straight from `matched` → `completed` via `riderCloseTrip` when
    // a rider self-closes before pickup — there's nothing to rate
    // because the riders never shared a cab. `startedAt` is only set
    // when the driver verifies OTP at pickup (see pickUpRider), so
    // it's the canonical "this ride genuinely happened" signal.
    const sibCompleted = await Trip.find(
      {
        matchGroup: { $in: groupIds },
        status: 'completed',
        startedAt: { $ne: null },
        _id: { $nin: myTripIds },
      },
      { _id: 1, rider: 1, matchGroup: 1 },
    ).populate('rider', 'name rating');
    if (sibCompleted.length === 0) return res.json({ pending: [] });

    // Map matchGroup → "my trip id in that group" so the response
    // can reference the trip from the user's perspective.
    const groupToMyTrip = new Map(
      myTrips.map((t) => [String(t.matchGroup), String(t._id)]),
    );

    // Filter out anyone the user already rated or skipped.
    const responseTargets = sibCompleted.map((t) => ({
      tripId: groupToMyTrip.get(String(t.matchGroup)),
      coRiderId: String(t.rider?._id || t.rider),
      coRiderName: t.rider?.name || 'Co-rider',
      coRiderRating: t.rider?.rating ?? 5,
      matchGroup: String(t.matchGroup),
    }));
    const targetUserIds = responseTargets.map((r) => r.coRiderId);

    const [rated, skipped] = await Promise.all([
      Rating.find({ fromUser: userObjId, toUser: { $in: targetUserIds } }, { toUser: 1, trip: 1 }),
      RatingSkip.find({ fromUser: userObjId, toUser: { $in: targetUserIds } }, { toUser: 1, trip: 1 }),
    ]);
    const respondedPairs = new Set([
      ...rated.map((r) => `${r.trip}|${r.toUser}`),
      ...skipped.map((r) => `${r.trip}|${r.toUser}`),
    ]);

    const pending = responseTargets.filter(
      (t) => !respondedPairs.has(`${t.tripId}|${t.coRiderId}`),
    );
    res.json({ pending });
  } catch (err) {
    next(err);
  }
}

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

// A leg is rateable iff the ride GENUINELY happened: status='completed'
// AND startedAt was set (which only fires when the driver verified the
// rider's OTP at pickup). Trips that flip straight from `matched` →
// `completed` via `riderCloseTrip` predate any actual shared ride and
// must not appear in rating prompts — the riders never sat in the
// same cab. See getMyPendingCoRiderRatings for the matching query
// guard at the listing layer.
function _isLegRateable(trip) {
  return trip.status === 'completed' && trip.startedAt != null;
}

// Find the sibling trip a given user is on within this trip's group
// (or the trip itself if they're the rider on it). Used to gate
// rating + skip on the target's leg being completed.
async function _legForUser(trip, userId) {
  if (String(trip.rider) === String(userId)) return trip;
  if (!trip.matchGroup) return null;
  const group = await MatchGroup.findById(trip.matchGroup);
  if (!group) return null;
  return Trip.findOne({
    _id: { $in: group.trips },
    rider: userId,
  });
}

module.exports = {
  rate,
  skipRating,
  getMyPendingCoRiderRatings,
  recomputeUserRating, // exported so tests + future flows can call it
};
