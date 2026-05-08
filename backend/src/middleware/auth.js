const jwt = require('jsonwebtoken');
const env = require('../config/env');
const { HttpError } = require('./errorHandler');

function signToken(user) {
  return jwt.sign(
    { sub: user._id.toString(), role: user.role },
    env.jwtSecret,
    { expiresIn: env.jwtExpiresIn },
  );
}

function requireAuth(req, _res, next) {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    return next(new HttpError(401, 'Missing bearer token'));
  }
  try {
    const decoded = jwt.verify(header.slice(7), env.jwtSecret);
    req.auth = { userId: decoded.sub, role: decoded.role };
    next();
  } catch {
    next(new HttpError(401, 'Invalid or expired token'));
  }
}

function requireRole(...roles) {
  return (req, _res, next) => {
    if (!req.auth || !roles.includes(req.auth.role)) {
      return next(new HttpError(403, 'Forbidden'));
    }
    next();
  };
}

module.exports = { signToken, requireAuth, requireRole };
