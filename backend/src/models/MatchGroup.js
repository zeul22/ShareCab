const mongoose = require('mongoose');

// A MatchGroup is the cab-share bundle: 2-3 trips going on the same cab.
// The matching engine creates and grows these.
const matchGroupSchema = new mongoose.Schema(
  {
    trips: [{ type: mongoose.Schema.Types.ObjectId, ref: 'Trip' }],
    driver: { type: mongoose.Schema.Types.ObjectId, ref: 'Driver', default: null },

    centroidPickup: {
      type: { type: String, enum: ['Point'], default: 'Point' },
      coordinates: { type: [Number], default: [0, 0] },
    },
    centroidDropoff: {
      type: { type: String, enum: ['Point'], default: 'Point' },
      coordinates: { type: [Number], default: [0, 0] },
    },

    status: {
      type: String,
      enum: ['forming', 'sealed', 'in_progress', 'completed', 'cancelled'],
      default: 'forming',
      index: true,
    },
  },
  { timestamps: true },
);

matchGroupSchema.index({ centroidPickup: '2dsphere' });
matchGroupSchema.index({ centroidDropoff: '2dsphere' });

module.exports = mongoose.model('MatchGroup', matchGroupSchema);
