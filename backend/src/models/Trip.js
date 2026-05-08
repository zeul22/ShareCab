const mongoose = require('mongoose');

const TRIP_STATUSES = [
  'requested',     // rider has requested, awaiting match / driver
  'matched',       // matched into a MatchGroup with co-rider(s)
  'driver_assigned',
  'arriving',      // driver en route to pickup
  'in_progress',   // ride underway
  'completed',
  'cancelled',
];

const tripSchema = new mongoose.Schema(
  {
    rider: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    driver: { type: mongoose.Schema.Types.ObjectId, ref: 'Driver', default: null, index: true },
    matchGroup: { type: mongoose.Schema.Types.ObjectId, ref: 'MatchGroup', default: null, index: true },

    pickup: {
      address: String,
      location: {
        type: { type: String, enum: ['Point'], default: 'Point' },
        coordinates: { type: [Number], required: true }, // [lng, lat]
      },
    },
    dropoff: {
      address: String,
      location: {
        type: { type: String, enum: ['Point'], default: 'Point' },
        coordinates: { type: [Number], required: true },
      },
    },

    // Whether the rider opted in to share with co-riders nearby.
    shareEnabled: { type: Boolean, default: true },

    status: { type: String, enum: TRIP_STATUSES, default: 'requested', index: true },

    // Estimated and actual fare (in smallest currency unit — paise/cents — or major; choose one and stick with it).
    fareEstimate: { type: Number },
    fareFinal: { type: Number },
    distanceKm: { type: Number },
    durationMin: { type: Number },

    requestedAt: { type: Date, default: Date.now },
    startedAt: { type: Date },
    completedAt: { type: Date },
    cancelledAt: { type: Date },
    cancelReason: { type: String },
  },
  { timestamps: true },
);

tripSchema.index({ 'pickup.location': '2dsphere' });
tripSchema.index({ 'dropoff.location': '2dsphere' });

tripSchema.statics.STATUSES = TRIP_STATUSES;

module.exports = mongoose.model('Trip', tripSchema);
