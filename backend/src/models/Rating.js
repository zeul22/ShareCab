const mongoose = require('mongoose');

const ratingSchema = new mongoose.Schema(
  {
    trip: { type: mongoose.Schema.Types.ObjectId, ref: 'Trip', required: true, index: true },
    fromUser: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    toUser: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },

    stars: { type: Number, min: 1, max: 5, required: true },
    comment: { type: String, maxlength: 500 },
  },
  { timestamps: true },
);

// One rating per (trip, fromUser, toUser) — lets a rider in a shared
// trip rate each of their co-riders + the driver as separate Rating
// rows. Previously the index was (trip, fromUser) which only made
// sense back when a rider only rated their driver.
ratingSchema.index({ trip: 1, fromUser: 1, toUser: 1 }, { unique: true });

module.exports = mongoose.model('Rating', ratingSchema);
