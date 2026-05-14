const { Server } = require('socket.io');
const jwt = require('jsonwebtoken');
const env = require('../config/env');
const Driver = require('../models/Driver');
const MatchGroup = require('../models/MatchGroup');
const User = require('../models/User');
const notifications = require('../services/notificationService');
const logger = require('../utils/logger');

/**
 * Realtime channels:
 *   - user:{userId}     private channel for trip updates / notifications
 *   - driver:{userId}   private channel for incoming ride offers
 *   - trip:{tripId}     everyone subscribed to a trip (rider + driver + admin)
 *   - group:{groupId}   chat room for the riders in a MatchGroup
 *
 * Events:
 *   - driver -> server:  'driver:location'  { lat, lng }
 *   - client -> server:  'group:subscribe'  groupId  (membership-checked)
 *   - server -> trip:    'trip:update'      { id, status, ... }
 *   - server -> trip:    'driver:location'  { driverId, lat, lng }
 *   - server -> group:   'chat:message'     { _id, sender, content, createdAt }
 *   - server -> group:   'chat:reset'       { groupId }
 *   - client -> server:  'chat:typing'      { groupId, state: 'start'|'stop' }
 *   - server -> group:   'chat:typing'      { groupId, userId, name, state }
 */
function attachSocketServer(httpServer) {
  const io = new Server(httpServer, {
    cors: { origin: process.env.CORS_ORIGIN?.split(',') || '*' },
  });

  io.use((socket, next) => {
    const token = socket.handshake.auth?.token;
    if (!token) return next(new Error('Missing token'));
    try {
      const decoded = jwt.verify(token, env.jwtSecret);
      socket.data.userId = decoded.sub;
      socket.data.role = decoded.role;
      next();
    } catch {
      next(new Error('Invalid token'));
    }
  });

  io.on('connection', (socket) => {
    const { userId, role } = socket.data;
    socket.join(`user:${userId}`);
    if (role === 'driver') socket.join(`driver:${userId}`);

    logger.debug(`socket connected user=${userId} role=${role}`);

    socket.on('trip:subscribe', (tripId) => {
      socket.join(`trip:${tripId}`);
    });
    socket.on('trip:unsubscribe', (tripId) => {
      socket.leave(`trip:${tripId}`);
    });

    // Chat room for a MatchGroup. Membership-checked: a stranger
    // sniffing groupIds can't subscribe to other riders' chats.
    socket.on('group:subscribe', async (groupId) => {
      try {
        const group = await MatchGroup.findById(groupId).populate({
          path: 'trips',
          select: 'rider',
        });
        const isMember = group?.trips?.some(
          (t) => t.rider && t.rider.toString() === userId,
        );
        if (!isMember) {
          logger.debug(`group:subscribe rejected user=${userId} group=${groupId}`);
          return;
        }
        socket.join(`group:${groupId}`);
      } catch (err) {
        logger.debug(`group:subscribe error: ${err.message}`);
      }
    });
    socket.on('group:unsubscribe', (groupId) => {
      socket.leave(`group:${groupId}`);
    });

    // Ephemeral "user is typing" pip. Only relayed to other members of
    // the group room — sender doesn't get an echo. We require the
    // socket to already be a member of `group:{groupId}` (which only
    // happens after a successful group:subscribe), so non-members
    // can't spam typing events at a chat they aren't part of.
    //
    // Display name is server-resolved (not client-supplied) and cached
    // on the socket for the rest of the connection lifetime.
    socket.on('chat:typing', async ({ groupId, state } = {}) => {
      if (!groupId) {
        logger.debug(`chat:typing rejected: no groupId from user=${userId}`);
        return;
      }
      const normalizedState = state === 'stop' ? 'stop' : 'start';
      // Membership gate: the socket must be subscribed to this group's
      // room (which only happens via a successful group:subscribe).
      // Without this check a malicious client could spam typing pips
      // at random groupIds they aren't a member of.
      if (!socket.rooms.has(`group:${groupId}`)) {
        logger.debug(
          `chat:typing rejected: socket=${socket.id} user=${userId} ` +
            `not in room group:${groupId}; rooms=${[...socket.rooms].join(',')}`,
        );
        return;
      }
      try {
        if (!socket.data.userName) {
          const u = await User.findById(userId).select('name').lean();
          const raw = (u?.name || '').trim();
          socket.data.userName = raw ? raw.split(' ')[0] : 'Co-rider';
        }
        logger.debug(
          `chat:typing relay user=${userId} name=${socket.data.userName} ` +
            `group=${groupId} state=${normalizedState}`,
        );
        socket.to(`group:${groupId}`).emit('chat:typing', {
          groupId: String(groupId),
          userId,
          name: socket.data.userName,
          state: normalizedState,
        });
      } catch (err) {
        logger.debug(`chat:typing error: ${err.message}`);
      }
    });

    socket.on('driver:location', async ({ lat, lng, tripId }) => {
      if (role !== 'driver') return;
      // Persist for dispatcher queries.
      await Driver.findOneAndUpdate(
        { user: userId },
        { $set: { currentLocation: { type: 'Point', coordinates: [lng, lat] } } },
      );
      if (tripId) {
        io.to(`trip:${tripId}`).emit('driver:location', { driverUserId: userId, lat, lng });
      }
    });

    socket.on('disconnect', () => {
      logger.debug(`socket disconnected user=${userId}`);
    });
  });

  notifications.bind(io);
  return io;
}

module.exports = { attachSocketServer };
