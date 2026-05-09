const { Server } = require('socket.io');
const jwt = require('jsonwebtoken');
const env = require('../config/env');
const Driver = require('../models/Driver');
const MatchGroup = require('../models/MatchGroup');
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
