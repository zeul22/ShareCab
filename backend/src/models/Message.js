const mongoose = require('mongoose');

// Per-group chat. Messages are deleted en masse whenever the group's
// composition changes (a rider leaves OR a new rider joins) — see
// tripController.cancelTrip and matchingService.joinGroup. Privacy-driven:
// a new joiner shouldn't see the prior pair's conversation.
const messageSchema = new mongoose.Schema(
  {
    matchGroup: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'MatchGroup',
      required: true,
      index: true,
    },
    sender: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    // 500-char cap is generous for a coordination message ("I'm at the gate
    // near the auto stand"). Keeps payloads tight; clients should validate too.
    content: {
      type: String,
      required: true,
      trim: true,
      maxlength: 500,
    },
  },
  { timestamps: true },
);

// Compound index for efficient time-ordered fetch within a group.
messageSchema.index({ matchGroup: 1, createdAt: 1 });

module.exports = mongoose.model('Message', messageSchema);
