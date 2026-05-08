const { z } = require('zod');
const User = require('../models/User');
const Driver = require('../models/Driver');
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

module.exports = { signup, login, me };
