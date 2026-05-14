const { z } = require('zod');
const User = require('../models/User');
const { HttpError } = require('../middleware/errorHandler');

async function getProfile(req, res, next) {
  try {
    const user = await User.findById(req.params.id);
    if (!user) throw new HttpError(404, 'User not found');
    res.json({ user: user.toPublicJSON() });
  } catch (err) {
    next(err);
  }
}

// Onboarding + later profile edits go through this same endpoint. Schema
// uses .partial() so callers can patch just one field (e.g. updating
// homeCity later) without re-submitting name + email. Onboarding submits
// all three at once.
const profileUpdateSchema = z
  .object({
    // Letters, spaces, apostrophes, dots, hyphens — covers Indian names
    // with initials/prefixes ("Dr. A. P. J. Abdul Kalam", "D'Souza").
    name: z
      .string()
      .trim()
      .min(2, 'Name must be at least 2 characters')
      .max(60, 'Name is too long')
      .regex(/^[\p{L}][\p{L}\s.'-]*$/u, 'Name has invalid characters'),
    email: z.string().trim().toLowerCase().email('Enter a valid email'),
    homeCity: z.string().trim().min(2).max(60).optional(),
  })
  .partial();

async function updateProfile(req, res, next) {
  try {
    if (req.params.id !== req.auth.userId && req.auth.role !== 'admin') {
      throw new HttpError(403, 'Cannot edit another user');
    }
    const update = profileUpdateSchema.parse(req.body);
    if (Object.keys(update).length === 0) {
      throw new HttpError(400, 'Nothing to update');
    }
    try {
      const user = await User.findByIdAndUpdate(
        req.params.id,
        { $set: update },
        { new: true, runValidators: true },
      );
      if (!user) throw new HttpError(404, 'User not found');
      res.json({ user: user.toPublicJSON() });
    } catch (err) {
      // Duplicate email — surface a clear 409 instead of leaking the
      // raw Mongo error. The `email` field has a sparse unique index;
      // any other duplicate is unexpected here.
      if (err && err.code === 11000) {
        throw new HttpError(409, 'That email is already in use');
      }
      throw err;
    }
  } catch (err) {
    next(err);
  }
}

module.exports = { getProfile, updateProfile };
