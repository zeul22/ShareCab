const cron = require('node-cron');
const subscriptionReminders = require('./subscriptionReminders');
const logger = require('../utils/logger');

// Single in-process scheduler. For multi-instance deploys, hoist this
// behind a leader-election layer (Redis / Mongo TTL doc / k8s leader
// election) so only one box runs each job. At our current scale a single
// node is fine.
//
// Cron expressions use 5 fields: minute hour dom month dow.
//   '0 9 * * *'  → every day at 09:00 server time
//
// Tip for ops: set TZ=Asia/Kolkata on the EC2 box so the 09:00 fires at
// 09:00 IST, not UTC.
function start() {
  // Daily 09:00 — pings drivers whose subscription expires in the next
  // SUBSCRIPTION_REMIND_DAYS_BEFORE (default 3) days. Idempotent thanks
  // to subscriptionReminderSentAt dedupe.
  cron.schedule('0 9 * * *', async () => {
    try {
      const result = await subscriptionReminders.runOnce();
      logger.info(
        `cron[subscription-reminders] reminded=${result.reminded} skipped=${result.skipped}`,
      );
    } catch (err) {
      logger.error(`cron[subscription-reminders] error: ${err.message}`);
    }
  });

  logger.info('Scheduler started: subscription-reminders @ 09:00 daily');
}

module.exports = { start };
