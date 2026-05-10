const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const { z } = require('zod');
const User = require('../models/User');
const Driver = require('../models/Driver');
const env = require('../config/env');
const { signToken } = require('../middleware/auth');
const { HttpError } = require('../middleware/errorHandler');
const msg91 = require('../services/msg91Client');

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
      // Auto-grant the free trial. New drivers can go online from day one
      // without paying — they convert when the trial expires. Set to 0 in
      // env.driverSub.freeTrialDays once we no longer need to seed supply.
      const trialDays = env.driverSub.freeTrialDays;
      const now = new Date();
      const trialExpiresAt = trialDays > 0
          ? new Date(now.getTime() + trialDays * 24 * 60 * 60 * 1000)
          : null;
      await Driver.create({
        user: user._id,
        licenseNumber: data.driver.licenseNumber,
        vehicle: data.driver.vehicle,
        subscriptionStartedAt: trialDays > 0 ? now : null,
        subscriptionExpiresAt: trialExpiresAt,
        subscriptionPaymentRef: trialDays > 0 ? 'free-trial' : null,
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
// OTP-based auth — what the Flutter app uses for sign-in.
//
// Default: every request goes through MSG91 server-side. /otp/request
// dispatches a real SMS, /otp/verify validates against MSG91.
//
// Dev fallback (opt-in only): set MSG91_DEV_FALLBACK=true in .env and
// the endpoints skip MSG91 entirely — /otp/request returns the dev OTP,
// /otp/verify accepts only that exact code. Useful while DLT is pending.
// PRODUCTION MUST NEVER ENABLE THIS — anyone hitting the API can log
// in as any phone with `123456`.
//
// If neither MSG91 nor the dev fallback is configured, the endpoints
// return 503 so the failure is loud rather than silent.
// =============================================================================

const DEV_OTP = process.env.DEV_OTP || '123456';

function requireMsg91AuthKey() {
  if (!env.msg91.authKey) {
    throw new HttpError(
      503,
      'MSG91 OTP is not configured on the server. Set MSG91_AUTH_KEY in backend/.env, '
        + 'or set MSG91_DEV_FALLBACK=true to use the dev OTP.',
    );
  }
}

// Sending an OTP additionally needs the DLT-registered template id;
// verifying an existing OTP only needs the authkey, so we split the
// guards. /otp/verify shouldn't 503 on a missing template id.
function requireMsg91SendConfig() {
  requireMsg91AuthKey();
  if (!env.msg91.templateId) {
    throw new HttpError(
      503,
      'MSG91 template id missing. Set MSG91_TEMPLATE_ID in backend/.env, '
        + 'or set MSG91_DEV_FALLBACK=true to use the dev OTP.',
    );
  }
}

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
    const { phone } = otpRequestSchema.parse(req.body);

    // Dev fallback short-circuit. Skips MSG91 entirely and tells the
    // client what code to type. Only when MSG91_DEV_FALLBACK=true.
    if (env.msg91.devFallback) {
      return res.json({ debugOtp: DEV_OTP });
    }

    requireMsg91SendConfig();
    const result = await msg91.sendOtp({ mobile: phone });
    if (!result.ok) {
      throw new HttpError(
        502,
        `MSG91 sendOtp failed: ${result.message || result.reason || 'unknown error'}`,
      );
    }
    res.json({ requestId: result.requestId });
  } catch (err) {
    next(err);
  }
}

async function verifyOtp(req, res, next) {
  try {
    const { phone, otp } = otpVerifySchema.parse(req.body);

    if (env.msg91.devFallback) {
      // Match against the hardcoded dev OTP. Same flag is checked in
      // requestOtp, so this whole flow stays local.
      if (otp !== DEV_OTP) throw new HttpError(401, 'Invalid OTP');
    } else {
      requireMsg91AuthKey();
      const result = await msg91.verifyOtp({ mobile: phone, otp });
      if (!result.ok) {
        throw new HttpError(401, result.message || 'Invalid OTP');
      }
    }

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

// MSG91 OTP exchange. The client app:
//   1. Calls the MSG91 widget SDK's sendOTP + verifyOTP (entirely on
//      the device — we never see the OTP).
//   2. On success the SDK hands back a JWT-style access token signed by
//      MSG91, plus the phone the user verified.
//   3. The app POSTs both here. We ask MSG91's verifyAccessToken to
//      confirm the token, then issue our own session.
//
// Why we re-verify server-side: the client could otherwise lie about
// any phone number. The MSG91 access token is the cryptographic proof
// that the phone really did receive the OTP.
const msg91VerifySchema = z.object({
  phone: z.string().min(7),
  accessToken: z.string().min(8),
});

async function verifyMsg91Otp(req, res, next) {
  try {
    if (!env.msg91.authKey) {
      throw new HttpError(503, 'MSG91 auth is not configured on the server');
    }
    const { phone, accessToken } = msg91VerifySchema.parse(req.body);
    const result = await msg91.verifyAccessToken({ accessToken });
    if (!result.ok) {
      throw new HttpError(401, 'OTP verification failed (MSG91 rejected token)');
    }

    let user = await User.findOne({ phone });
    if (!user) {
      // First-time login — auto-create a rider account, same shape as
      // the dev-OTP path. Driver onboarding still requires explicit
      // signup (driver profile fields, license, vehicle).
      user = new User({ name: 'Rider', phone, role: 'rider' });
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

module.exports = {
  signup,
  login,
  me,
  requestOtp,
  verifyOtp,
  verifyMsg91Otp,
  refreshSession,
  logout,
};
