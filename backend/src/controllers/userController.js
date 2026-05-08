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

async function updateProfile(req, res, next) {
  try {
    if (req.params.id !== req.auth.userId && req.auth.role !== 'admin') {
      throw new HttpError(403, 'Cannot edit another user');
    }
    const { name, email, homeCity } = req.body;
    const user = await User.findByIdAndUpdate(
      req.params.id,
      { $set: { name, email, homeCity } },
      { new: true },
    );
    if (!user) throw new HttpError(404, 'User not found');
    res.json({ user: user.toPublicJSON() });
  } catch (err) {
    next(err);
  }
}

module.exports = { getProfile, updateProfile };
