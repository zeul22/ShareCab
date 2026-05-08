const { z } = require('zod');
const Rating = require('../models/Rating');
const Trip = require('../models/Trip');
const User = require('../models/User');
const { HttpError } = require('../middleware/errorHandler');

const rateSchema = z.object({
  tripId: z.string(),
  toUserId: z.string(),
  stars: z.number().int().min(1).max(5),
  comment: z.string().max(500).optional(),
});

async function rate(req, res, next) {
  try {
    const data = rateSchema.parse(req.body);

    const trip = await Trip.findById(data.tripId);
    if (!trip) throw new HttpError(404, 'Trip not found');
    if (trip.status !== 'completed') throw new HttpError(400, 'Can only rate completed trips');

    const rating = await Rating.create({
      trip: trip._id,
      fromUser: req.auth.userId,
      toUser: data.toUserId,
      stars: data.stars,
      comment: data.comment,
    });

    // Recompute the rated user's running average.
    const agg = await Rating.aggregate([
      { $match: { toUser: rating.toUser } },
      { $group: { _id: '$toUser', avg: { $avg: '$stars' }, count: { $sum: 1 } } },
    ]);
    if (agg[0]) {
      await User.findByIdAndUpdate(rating.toUser, { $set: { rating: agg[0].avg } });
    }

    res.status(201).json({ rating });
  } catch (err) {
    if (err.code === 11000) return next(new HttpError(409, 'Already rated this trip'));
    next(err);
  }
}

module.exports = { rate };
