// One-shot smoke driver. Connects to the live dev Mongo, sets the demo
// driver's subscription to expire in ~2 days (inside the 3-day window),
// runs the cron job twice — first run should remind, second should skip
// (dedupe via subscriptionReminderSentAt).
const mongoose = require('mongoose');
process.env.MONGODB_URI = 'mongodb://localhost:27017/sharecab';
const env = require('../src/config/env');
// Register User model BEFORE the reminder job tries to populate('user').
require('../src/models/User');
const Driver = require('../src/models/Driver');
const reminders = require('../src/scheduler/subscriptionReminders');

(async () => {
  await mongoose.connect(env.mongoUri);

  // Seed: demo driver expiring in 2 days, no prior reminder.
  const driver = await Driver.findOne().sort({ createdAt: -1 });
  if (!driver) { console.log('no driver in db'); process.exit(1); }
  driver.subscriptionExpiresAt = new Date(Date.now() + 2 * 24 * 60 * 60 * 1000);
  driver.subscriptionReminderSentAt = null;
  await driver.save();
  console.log('seed: driver=', driver._id.toString(), 'expiresAt=', driver.subscriptionExpiresAt.toISOString());

  console.log('\n── First run: should remind 1 ──');
  const r1 = await reminders.runOnce();
  console.log('result:', r1);

  console.log('\n── Second run (immediate): should skip 1 (dedupe) ──');
  const r2 = await reminders.runOnce();
  console.log('result:', r2);

  console.log('\n── After paid renewal, dedupe should clear ──');
  const fresh = await Driver.findById(driver._id);
  console.log('after-1st reminderSentAt:', fresh.subscriptionReminderSentAt?.toISOString());
  // Simulate a renewal clearing the dedupe.
  fresh.subscriptionReminderSentAt = null;
  fresh.subscriptionExpiresAt = new Date(Date.now() + 2 * 24 * 60 * 60 * 1000);
  await fresh.save();
  const r3 = await reminders.runOnce();
  console.log('after-clear run:', r3);

  await mongoose.disconnect();
})().catch(e => { console.error(e); process.exit(1); });
