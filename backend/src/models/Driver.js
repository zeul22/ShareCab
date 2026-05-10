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

    // Trips the driver is currently committed to. Solo dispatch sets one entry;
    // a shared MatchGroup sets one entry per co-rider. Empty ⇒ driver is free.
    activeTrips: [{ type: mongoose.Schema.Types.ObjectId, ref: 'Trip' }],

    // Monthly subscription. Drivers must have a non-expired subscription to
    // go online (see driverController.setOnline). New drivers get a free
    // first month set in authController.signup; subsequent renewals extend
    // expiresAt by env.driverSub.daysPerCycle. Razorpay will plug into the
    // /subscribe and /subscribe/confirm endpoints when wired live.
    subscriptionStartedAt: { type: Date, default: null },
    subscriptionExpiresAt: { type: Date, default: null, index: true },
    subscriptionPaymentRef: { type: String, default: null },
    // Stamped by the expiry-reminder cron when a "renew soon" notification
    // fires for the *current* subscription cycle. Cleared on successful
    // renewal (see paymentController.activateDriverSubscription) so the
    // next cycle's reminder isn't deduped.
    subscriptionReminderSentAt: { type: Date, default: null },
  },
  { timestamps: true },
);

driverSchema.virtual('isSubscribed').get(function checkSubscribed() {
  const exp = this.subscriptionExpiresAt;
  return exp != null && exp.getTime() > Date.now();
});

driverSchema.index({ currentLocation: '2dsphere' });

module.exports = mongoose.model('Driver', driverSchema);
