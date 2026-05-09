const mongoose = require('mongoose');

// A single-use grant that lets a rider use ride-partner matching on one trip.
// Created either by AdMob server-side verification (after the rider watches
// 2 rewarded ads) or by a Razorpay payment webhook. Consumed by the trip
// request handler when `shareEnabled=true`.
const unlockSchema = new mongoose.Schema(
  {
    rider: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    source: { type: String, enum: ['ad', 'payment'], required: true },

    // External reference for traceability — AdMob ad session id or Razorpay payment id.
    externalRef: { type: String },

    // For source='payment': amount captured, in paise.
    amountPaise: { type: Number },

    expiresAt: { type: Date, required: true },
    usedAt: { type: Date, default: null },
    usedForTrip: { type: mongoose.Schema.Types.ObjectId, ref: 'Trip', default: null },
  },
  { timestamps: true },
);

// Fast lookup of a rider's still-usable unlocks.
unlockSchema.index({ rider: 1, usedAt: 1, expiresAt: 1 });

module.exports = mongoose.model('Unlock', unlockSchema);
