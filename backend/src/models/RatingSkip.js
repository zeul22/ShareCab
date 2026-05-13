const mongoose = require('mongoose');

// Record of a rider explicitly skipping the co-rider rating prompt.
// Distinct from a Rating: "skipped" carries a -0.25 penalty on the
// skipper's own rating, surfaces in the audit trail, and prevents the
// app from re-prompting for the same (trip, target) pair.
//
// We could have folded this into Rating with a synthetic stars=0 row,
// but keeping it separate means the Rating average computation stays
// honest — only actual stars feed the average — and the User.rating
// effective score subtracts skips as a distinct term.
//
// Effective rating model:
//   effective = clamp(avg(received Ratings.stars) - 0.25 * count(my skips), 1, 5)
//
// See ratingController.recomputeUserRating.
const ratingSkipSchema = new mongoose.Schema(
  {
    trip: { type: mongoose.Schema.Types.ObjectId, ref: 'Trip', required: true, index: true },
    fromUser: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    toUser: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  },
  { timestamps: true },
);

// One skip per (trip, fromUser, toUser). Same shape as the Rating
// uniqueness so a rider can't simultaneously skip AND rate the same
// co-rider on the same trip — the controllers enforce the choice
// by checking both collections before writing.
ratingSkipSchema.index({ trip: 1, fromUser: 1, toUser: 1 }, { unique: true });

module.exports = mongoose.model('RatingSkip', ratingSkipSchema);
