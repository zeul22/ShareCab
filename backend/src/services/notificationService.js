const logger = require('../utils/logger');

/**
 * Notification service stub.
 *
 * In production this should integrate with:
 *   - Firebase Cloud Messaging (FCM) for Android / iOS push
 *   - Apple Push Notification service (APNS) for iOS direct
 *   - Twilio (or equivalent) for SMS fallback
 *   - Socket.IO for in-app realtime banners
 *
 * For now we log and emit through the socket layer when available.
 */
let io = null;

function bind(socketServer) {
  io = socketServer;
}

async function notifyUser(userId, event, payload) {
  logger.info(`[notify] user=${userId} event=${event}`);
  if (io) io.to(`user:${userId}`).emit(event, payload);
}

async function notifyDriver(driverId, event, payload) {
  logger.info(`[notify] driver=${driverId} event=${event}`);
  if (io) io.to(`driver:${driverId}`).emit(event, payload);
}

async function broadcastTripUpdate(trip) {
  if (!io) return;
  io.to(`trip:${trip._id}`).emit('trip:update', {
    id: trip._id,
    status: trip.status,
    driver: trip.driver,
    matchGroup: trip.matchGroup,
  });
}

module.exports = { bind, notifyUser, notifyDriver, broadcastTripUpdate };
