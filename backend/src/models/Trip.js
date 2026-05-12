const mongoose = require('mongoose');

const TRIP_STATUSES = [
  'requested',       // rider has requested, awaiting match / driver
  'matched',         // matched into a MatchGroup with co-rider(s)
  'offered',         // dispatched to ONE driver, awaiting their accept/reject
  'driver_assigned', // driver accepted; cab is committed
  'arriving',        // driver en route to pickup
  'in_progress',     // ride underway
  'completed',
  'cancelled',
];

const tripSchema = new mongoose.Schema(
  {
    rider: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    driver: { type: mongoose.Schema.Types.ObjectId, ref: 'Driver', default: null, index: true },
    matchGroup: { type: mongoose.Schema.Types.ObjectId, ref: 'MatchGroup', default: null, index: true },

    // Outstanding offer state. Populated when status='offered': the trip
    // has been dispatched to ONE driver and is waiting for their explicit
    // accept/reject (or the offer-expiry timer to fire and re-dispatch).
    // Cleared on accept (status flips to driver_assigned) or reject
    // (status flips back to 'requested' for re-dispatch). Flat fields
    // rather than a sub-document so we can $set/$unset atomically.
    offeredTo: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Driver',
      default: null,
      index: true,
    },
    offerExpiresAt: { type: Date, default: null },
    // Drivers who already rejected this trip. Keeps the re-dispatch loop
    // from re-offering to the same driver. Cleared on final assignment
    // (driver_assigned) so a later cancel-and-rebook flow starts fresh.
    rejectedBy: [{ type: mongoose.Schema.Types.ObjectId, ref: 'Driver' }],

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

    // Actual GPS at the moment the driver tapped "Picked up" / "Dropped".
    // Distinct from `pickup` / `dropoff` (where the rider tapped on the
    // map at request time) — the cab usually stops where it can pull
    // over, sometimes 30-50m away from the requested pin. Recorded for:
    //   - rider's map source/destination pin snap once trip is in_progress
    //   - fare reconciliation + dispute audit
    //   - future: driver-side trip review ("you completed at the right place")
    actualPickup: {
      location: {
        type: { type: String, enum: ['Point'], default: 'Point' },
        coordinates: { type: [Number] }, // [lng, lat]
      },
      recordedAt: Date,
    },
    actualDropoff: {
      location: {
        type: { type: String, enum: ['Point'], default: 'Point' },
        coordinates: { type: [Number] },
      },
      recordedAt: Date,
    },

    // Whether the rider opted in to share with co-riders nearby.
    shareEnabled: { type: Boolean, default: true },

    status: { type: String, enum: TRIP_STATUSES, default: 'requested', index: true },

    // Fare totals, in PAISE (1 INR = 100 paise). Matches Razorpay's
    // amount field — no ×100 acrobatics. Denormalized from
    // `fareBreakdown.total` so legacy read paths keep working.
    fareEstimate: { type: Number },
    fareFinal: { type: Number },
    distanceKm: { type: Number },
    durationMin: { type: Number },
    // Structured fare breakdown from fareService.quoteSolo /
    // .quoteShared. Stored as Mixed so the shape can evolve without
    // schema migrations — the source of truth for what the rider sees
    // on the confirmation + payment screens and what the driver sees
    // as their take-home. Always present after pricing; rewritten with
    // actual values at settlement time.
    fareBreakdown: { type: mongoose.Schema.Types.Mixed },

    requestedAt: { type: Date, default: Date.now },
    startedAt: { type: Date },
    completedAt: { type: Date },
    cancelledAt: { type: Date },
    cancelReason: { type: String },

    // Rider-only mode: timestamp at which this rider unlocked the
    // matched-group reveal (paid or watched ads). Null while the match
    // is still gated. The getTrip controller uses this to decide
    // whether to populate co-rider details or return a redacted view.
    // Unused in driver-dispatch mode (we leave it null).
    matchRevealedAt: { type: Date, default: null },

    // 4-digit pickup OTP. Generated server-side at trip creation so the
    // value can't be forged client-side; the driver enters it from the
    // rider's phone when arriving at THIS rider's pickup stop. Each trip
    // in a shared group has its own OTP so a co-rider's OTP can't
    // pick up the wrong person. Verified in pickUpRider.
    otp: { type: String },

    // Per-rider "find cab" consent. Shared trips don't dispatch until
    // every rider in the matchGroup has tapped Find Cab, so neither
    // rider gets a driver while the other is still deciding. Solo
    // trips dispatch immediately on creation and skip this gate.
    // See find-cab + tripController.requestTrip.
    readyToFindCab: { type: Boolean, default: false, index: true },
  },
  { timestamps: true },
);

tripSchema.index({ 'pickup.location': '2dsphere' });
tripSchema.index({ 'dropoff.location': '2dsphere' });

tripSchema.statics.STATUSES = TRIP_STATUSES;

module.exports = mongoose.model('Trip', tripSchema);
