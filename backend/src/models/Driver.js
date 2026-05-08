const mongoose = require('mongoose');

// A 2dsphere index on `currentLocation` powers the "find nearby drivers" query.
const driverSchema = new mongoose.Schema(
  {
    user: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, unique: true },

    licenseNumber: { type: String, required: true },
    vehicle: {
      model: { type: String, required: true },
      plate: { type: String, required: true, uppercase: true },
      color: { type: String },
      capacity: { type: Number, default: 4 },
    },

    isOnline: { type: Boolean, default: false, index: true },
    currentLocation: {
      type: { type: String, enum: ['Point'], default: 'Point' },
      coordinates: { type: [Number], default: [0, 0] }, // [lng, lat]
    },

    activeTrip: { type: mongoose.Schema.Types.ObjectId, ref: 'Trip', default: null },
  },
  { timestamps: true },
);

driverSchema.index({ currentLocation: '2dsphere' });

module.exports = mongoose.model('Driver', driverSchema);
