const logger = require('../utils/logger');

function notFoundHandler(req, res, _next) {
  res.status(404).json({ error: 'Not found', path: req.originalUrl });
}

// eslint-disable-next-line no-unused-vars
function errorHandler(err, req, res, _next) {
  const status = err.status || err.statusCode || 500;
  if (status >= 500) {
    // Defensive: some error objects (notably Zod's ZodError) have
    // getter-backed properties that throw inside Node's util.inspect,
    // which would otherwise swallow the original error and surface as
    // "TypeError: Cannot read properties of undefined (reading
    // 'value')" — making real 500s unreadable. Log the bits we know
    // are safe (message + stack) and fall back to a generic line on
    // anything weirder.
    try {
      logger.error(
        `Unhandled ${req.method} ${req.originalUrl}: ${err?.message || err}`,
      );
      if (err?.stack) logger.error(err.stack);
    } catch (_) {
      logger.error(`Unhandled ${req.method} ${req.originalUrl} (unprintable error)`);
    }
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
