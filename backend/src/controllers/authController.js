const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const { z } = require('zod');
const User = require('../models/User');
const Driver = require('../models/Driver');
const env = require('../config/env');
const { signToken } = require('../middleware/auth');
const { HttpError } = require('../middleware/errorHandler');

const signupSchema = z.object({
  name: z.string().min(2),
  phone: z.string().min(7),
  email: z.string().email().optional(),
  password: z.string().min(6),
  role: z.enum(['rider', 'driver']).default('rider'),
  driver: z
    .object({
      licenseNumber: z.string().min(2),
      vehicle: z.object({
        model: z.string(),
        plate: z.string(),
        color: z.string().optional(),
        capacity: z.number().int().min(1).max(8).optional(),
      }),
    })
    .optional(),
});

const loginSchema = z.object({
  phone: z.string().min(7),
  password: z.string().min(6),
});

async function signup(req, res, next) {
  try {
    const data = signupSchema.parse(req.body);
    const existing = await User.findOne({ phone: data.phone });
    if (existing) throw new HttpError(409, 'Phone already registered');

    const user = new User({
      name: data.name,
      phone: data.phone,
      email: data.email,
      role: data.role,
    });
    await user.setPassword(data.password);
    await user.save();

    if (data.role === 'driver') {
      if (!data.driver) throw new HttpError(400, 'Driver profile is required when role=driver');
      await Driver.create({
        user: user._id,
        licenseNumber: data.driver.licenseNumber,
        vehicle: data.driver.vehicle,
      });
    }

    const token = signToken(user);
    res.status(201).json({ token, user: user.toPublicJSON() });
  } catch (err) {
    next(err);
  }
}

async function login(req, res, next) {
  try {
    const data = loginSchema.parse(req.body);
    const user = await User.findOne({ phone: data.phone });
    if (!user || !(await user.checkPassword(data.password))) {
      throw new HttpError(401, 'Invalid phone or password');
    }
    const token = signToken(user);
    res.json({ token, user: user.toPublicJSON() });
  } catch (err) {
    next(err);
  }
}

async function me(req, res, next) {
  try {
    const user = await User.findById(req.auth.userId);
    if (!user) throw new HttpError(404, 'User not found');
    res.json({ user: user.toPublicJSON() });
  } catch (err) {
    next(err);
  }
}

// =============================================================================
// OTP-based auth — what the Flutter app actually uses.
// In dev, every phone gets the same hardcoded OTP "123456" so we can log in
// without an SMS gateway. Real prod hooks should:
//   - Generate a per-phone random OTP, store with TTL (Redis preferred)
//   - Send via MSG91 / Twilio / etc.
//   - Rate-limit by phone + IP (current /api router's rate limit is too coarse)
// =============================================================================

const DEV_OTP = process.env.DEV_OTP || '123456';

const otpRequestSchema = z.object({
  // Indian mobile: 10 digits starting 6-9 (optionally +91 prefix or spaces).
  phone: z.string().min(7).max(16),
});

const otpVerifySchema = z.object({
  phone: z.string().min(7).max(16),
  otp: z.string().length(6),
});

const refreshSchema = z.object({
  refreshToken: z.string().min(1),
});

async function requestOtp(req, res, next) {
  try {
    otpRequestSchema.parse(req.body);
    // TODO(sms-provider): generate per-phone OTP, store with TTL, send via provider.
    res.json({ debugOtp: DEV_OTP });
  } catch (err) {
    next(err);
  }
}

async function verifyOtp(req, res, next) {
  try {
    const { phone, otp } = otpVerifySchema.parse(req.body);
    if (otp !== DEV_OTP) throw new HttpError(401, 'Invalid OTP');

    let user = await User.findOne({ phone });
    if (!user) {
      // First-time login — auto-create a rider account. The app exposes no
      // signup form; verifyOtp doubles as signup.
      user = new User({
        name: 'Rider',
        phone,
        role: 'rider',
      });
      // OTP-only users have no usable password — set a random unguessable one
      // so the password login path can never authenticate as them.
      await user.setPassword(crypto.randomBytes(32).toString('hex'));
      await user.save();
    }
    res.json(issueSession(user));
  } catch (err) {
    next(err);
  }
}

async function refreshSession(req, res, next) {
  try {
    const { refreshToken } = refreshSchema.parse(req.body);
    let payload;
    try {
      payload = jwt.verify(refreshToken, env.jwtSecret);
    } catch {
      throw new HttpError(401, 'Invalid or expired refresh token');
    }
    const user = await User.findById(payload.sub);
    if (!user) throw new HttpError(404, 'User not found');
    res.json(issueSession(user));
  } catch (err) {
    next(err);
  }
}

async function logout(_req, res, next) {
  try {
    // No revocation list yet — client-side drop is enough for now.
    // TODO: maintain a revoked-jti set (Redis) when going to prod.
    res.status(204).send();
  } catch (err) {
    next(err);
  }
}

function issueSession(user) {
  const token = signToken(user); // 7d JWT
  // Same token for both fields. Real refresh-token rotation is a follow-up;
  // the app's auto-refresh path will still exercise correctly because we tell
  // it the access token expires in 6 days (just under JWT exp).
  const accessExpiresAt = new Date(Date.now() + 6 * 24 * 60 * 60 * 1000);
  return {
    accessToken: token,
    refreshToken: token,
    accessExpiresAt: accessExpiresAt.toISOString(),
    user: user.toPublicJSON(),
  };
}

module.exports = { signup, login, me, requestOtp, verifyOtp, refreshSession, logout };
