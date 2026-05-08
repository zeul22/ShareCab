const logger = require('../utils/logger');

function notFoundHandler(req, res, _next) {
  res.status(404).json({ error: 'Not found', path: req.originalUrl });
}

// eslint-disable-next-line no-unused-vars
function errorHandler(err, req, res, _next) {
  const status = err.status || err.statusCode || 500;
  if (status >= 500) {
    logger.error('Unhandled error', err);
  }
  res.status(status).json({
    error: err.publicMessage || err.message || 'Internal server error',
    ...(err.details ? { details: err.details } : {}),
  });
}

class HttpError extends Error {
  constructor(status, message, details) {
    super(message);
    this.status = status;
    this.publicMessage = message;
    this.details = details;
  }
}

module.exports = { errorHandler, notFoundHandler, HttpError };
