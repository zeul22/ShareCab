const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

const userSchema = new mongoose.Schema(
  {
    name: { type: String, required: true, trim: true },
    phone: { type: String, required: true, unique: true, index: true },
    email: { type: String, lowercase: true, trim: true, sparse: true, unique: true },
    passwordHash: { type: String, required: true },

    role: { type: String, enum: ['rider', 'driver', 'admin'], default: 'rider', index: true },

    rating: { type: Number, default: 5.0, min: 1, max: 5 },
    totalRides: { type: Number, default: 0 },

    homeCity: { type: String },
    isActive: { type: Boolean, default: true },
  },
  { timestamps: true },
);

userSchema.methods.setPassword = async function setPassword(plain) {
  this.passwordHash = await bcrypt.hash(plain, 10);
};

userSchema.methods.checkPassword = function checkPassword(plain) {
  return bcrypt.compare(plain, this.passwordHash);
};

userSchema.methods.toPublicJSON = function toPublicJSON() {
  return {
    id: this._id,
    name: this.name,
    phone: this.phone,
    email: this.email,
    role: this.role,
    rating: this.rating,
    totalRides: this.totalRides,
    // True once the rider has gone through the onboarding form. Derived,
    // not stored: a fresh rider is created with the placeholder name
    // 'Rider' and no email, and we treat any user with a real name + an
    // email as having completed onboarding. The app routes incomplete
    // users to OnboardingScreen on next login. Drivers are onboarded via
    // a separate flow (vehicle + license), so we skip the gate for them.
    profileCompleted:
      this.role === 'driver' ||
      Boolean(this.name && this.name !== 'Rider' && this.email),
  };
};

module.exports = mongoose.model('User', userSchema);
