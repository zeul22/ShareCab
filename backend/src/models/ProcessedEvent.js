const mongoose = require('mongoose');

// Idempotency log for inbound webhooks (Razorpay today; AdMob SSV later).
// Razorpay retries on any non-2xx response, but Cloud Run timeouts and
// transient failures also cause duplicates even on successful processing.
// We dedupe by the upstream event id — once we've recorded it here, the
// webhook handler short-circuits before re-applying any state change.
//
// `source` lets us scope idempotency per provider so the same id from two
// providers doesn't collide. `expiresAt` is a TTL — keeping events forever
// would balloon the collection; 30 days is long past Razorpay's retry
// window (a few hours) but short enough to keep the index cheap.
const processedEventSchema = new mongoose.Schema(
  {
    source: { type: String, required: true, enum: ['razorpay', 'admob'] },
    eventId: { type: String, required: true },
    // Free-form for audit. We stash the event type ('payment.captured') +
    // the related entity id (paymentId / driverId / riderId) so the log
    // is greppable without re-pulling the payload.
    summary: { type: String },
    expiresAt: { type: Date, required: true },
  },
  { timestamps: true },
);

// Unique per (source, eventId) — duplicate inserts throw E11000 which the
// caller turns into "already processed, skip."
processedEventSchema.index({ source: 1, eventId: 1 }, { unique: true });
// MongoDB TTL index — docs auto-delete `expiresAt` seconds after the
// timestamp it carries. `expireAfterSeconds: 0` means "at the date stored
// in expiresAt", which is the standard TTL idiom.
processedEventSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });

module.exports = mongoose.model('ProcessedEvent', processedEventSchema);
