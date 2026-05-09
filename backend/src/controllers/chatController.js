const { z } = require('zod');
const Message = require('../models/Message');
const MatchGroup = require('../models/MatchGroup');
const notifications = require('../services/notificationService');
const { HttpError } = require('../middleware/errorHandler');

// Verify the requesting user is one of the riders currently in the group.
// Rejects 404 (group missing) or 403 (not a member) — never leaks group
// existence to non-members. Returns the populated group for reuse.
async function ensureGroupMembership(groupId, userId) {
  const group = await MatchGroup.findById(groupId).populate({
    path: 'trips',
    select: 'rider',
  });
  if (!group) throw new HttpError(404, 'Group not found');
  const isMember = (group.trips || []).some(
    (t) => t.rider && t.rider.toString() === userId,
  );
  if (!isMember) throw new HttpError(403, 'Not a member of this group');
  return group;
}

const postSchema = z.object({
  content: z.string().min(1).max(500),
});

async function listMessages(req, res, next) {
  try {
    const { groupId } = req.params;
    await ensureGroupMembership(groupId, req.auth.userId);

    // Last 100 in chronological order — plenty for coordination chat,
    // pagination can be added (cursor or skip) when group sessions get long.
    const messages = await Message.find({ matchGroup: groupId })
      .sort({ createdAt: 1 })
      .limit(100)
      .populate({ path: 'sender', select: 'name rating' });

    res.json({ messages });
  } catch (err) {
    next(err);
  }
}

async function postMessage(req, res, next) {
  try {
    const { groupId } = req.params;
    const { content } = postSchema.parse(req.body);
    await ensureGroupMembership(groupId, req.auth.userId);

    const created = await Message.create({
      matchGroup: groupId,
      sender: req.auth.userId,
      content,
    });

    // Re-fetch with sender populated so all clients get a uniform shape
    // whether they receive via REST response, socket event, or REST refetch.
    const populated = await Message.findById(created._id)
      .populate({ path: 'sender', select: 'name rating' });

    // Fan out to every rider currently subscribed to this group's room.
    notifications.broadcastChatMessage(groupId, populated);

    res.status(201).json({ message: populated });
  } catch (err) {
    next(err);
  }
}

module.exports = { listMessages, postMessage };
