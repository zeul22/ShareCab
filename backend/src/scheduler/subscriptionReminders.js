const Driver = require('../models/Driver');
const env = require('../config/env');
const logger = require('../utils/logger');
const notifications = require('../services/notificationService');

// How many days before expiry we ping the driver. Configurable via env so
// ops can A/B (e.g. ping at 5 days for high-LTV markets where renewal
// hesitation is higher).
const REMIND_DAYS_BEFORE = Number(process.env.SUBSCRIPTION_REMIND_DAYS_BEFORE) || 3;

/**
 * Daily cron-friendly task. Finds drivers whose subscription expires in
 * the next REMIND_DAYS_BEFORE days AND who haven't already been reminded
 * this cycle, then notifies them to renew.
 *
 * Idempotency: subscriptionReminderSentAt is stamped on dispatch; the
 * reset to null lives in:
 *   - paymentController.activateDriverSubscription (webhook-driven renewal)
 *   - driverController.confirmSubscription      (rest-driven renewal)
 * So the same driver gets at most one reminder per subscription cycle.
 *
 * Safe to invoke directly from tests/admin without the scheduler — it's
 * just a function.
 */
async function runOnce({ now = new Date() } = {}) {
  const windowEnd = new Date(now.getTime() + REMIND_DAYS_BEFORE * 24 * 60 * 60 * 1000);

  const candidates = await Driver.find({
    subscriptionExpiresAt: { $gt: now, $lte: windowEnd },
    $or: [
      { subscriptionReminderSentAt: null },
      { subscriptionReminderSentAt: { $exists: false } },
    ],
  }).populate({ path: 'user', select: 'name phone' });

  if (candidates.length === 0) {
    return { reminded: 0, skipped: 0 };
  }

  let reminded = 0;
  for (const driver of candidates) {
    const userId = driver.user?._id ?? driver.user;
    const phone = driver.user?.phone || 'unknown';
    const expiresAt = driver.subscriptionExpiresAt;
    const daysLeft = Math.max(
      0,
      Math.ceil((expiresAt.getTime() - now.getTime()) / (24 * 60 * 60 * 1000)),
    );

    // Notify via socket (real-time banner if app is open) + log line.
    // FCM push for closed-app delivery is the documented follow-up
    // (app/docs/notifications.md); plug in there when ready.
    try {
      await notifications.notifyUser(userId, 'subscription:expiring', {
        driverId: String(driver._id),
        expiresAt: expiresAt.toISOString(),
        daysLeft,
        pricePaise: env.driverSub.pricePaise,
      });
      logger.info(
        `subscription-reminder driver=${driver._id} phone=${phone} ` +
        `expires=${expiresAt.toISOString()} daysLeft=${daysLeft}`,
      );
      driver.subscriptionReminderSentAt = now;
      await driver.save();
      reminded += 1;
    } catch (err) {
      logger.error(`subscription-reminder failed driver=${driver._id}: ${err.message}`);
    }
  }
  return { reminded, skipped: candidates.length - reminded };
}

module.exports = { runOnce, REMIND_DAYS_BEFORE };
