const { Server } = require('socket.io');
const jwt = require('jsonwebtoken');
const env = require('../config/env');
const Driver = require('../models/Driver');
const notifications = require('../services/notificationService');
const logger = require('../utils/logger');

/**
 * Realtime channels:
 *   - user:{userId}    private channel for trip updates / notifications
 *   - driver:{userId}  private channel for incoming ride offers
 *   - trip:{tripId}    everyone subscribed to a trip (rider + driver + admin)
 *
 * Events:
 *   - driver -> server:  'driver:location' { lat, lng }
 *   - server -> trip:    'trip:update'     { id, status, ... }
 *   - server -> trip:    'driver:location' { driverId, lat, lng }
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
