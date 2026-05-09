const { z } = require('zod');
const Driver = require('../models/Driver');
const { HttpError } = require('../middleware/errorHandler');
const { isWithinIndia } = require('../utils/geo');

const locationSchema = z
  .object({
    lat: z.number().min(-90).max(90),
    lng: z.number().min(-180).max(180),
  })
  .refine(isWithinIndia, { message: 'Coordinates must be within India' });

async function setOnline(req, res, next) {
  try {
    const driver = await Driver.findOneAndUpdate(
      { user: req.auth.userId },
      { $set: { isOnline: true } },
      { new: true },
    );
    if (!driver) throw new HttpError(404, 'Driver profile not found');
    res.json({ driver });
  } catch (err) {
    next(err);
  }
}

async function setOffline(req, res, next) {
  try {
    const driver = await Driver.findOneAndUpdate(
      { user: req.auth.userId },
      { $set: { isOnline: false } },
      { new: true },
    );
    if (!driver) throw new HttpError(404, 'Driver profile not found');
    res.json({ driver });
  } catch (err) {
    next(err);
  }
}

async function updateLocation(req, res, next) {
  try {
    const { lat, lng } = locationSchema.parse(req.body);
    const driver = await Driver.findOneAndUpdate(
      { user: req.auth.userId },
      { $set: { currentLocation: { type: 'Point', coordinates: [lng, lat] } } },
      { new: true },
    );
    if (!driver) throw new HttpError(404, 'Driver profile not found');
    res.json({ driver });
  } catch (err) {
    next(err);
  }
}

module.exports = { setOnline, setOffline, updateLocation };
