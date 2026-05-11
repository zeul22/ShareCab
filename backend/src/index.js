require('dotenv').config();
const http = require('http');
const app = require('./app');
const { connectDatabase } = require('./config/database');
const env = require('./config/env');
const { attachSocketServer } = require('./sockets');
const scheduler = require('./scheduler');
const logger = require('./utils/logger');

const PORT = process.env.PORT || 4000;

async function start() {
  await connectDatabase();

  const server = http.createServer(app);
  attachSocketServer(server);
  // Start cron jobs after DB is up + sockets bound. The scheduler sits in
  // the same process — fine for a single instance; behind a leader lock
  // when we go multi-node (see scheduler/index.js comment).
  scheduler.start();

  server.listen(PORT, () => {
    logger.info(`ShareCab API listening on http://localhost:${PORT}`);
    // Surface OTP routing so you know at a glance which path is live.
    if (env.msg91.devFallback) {
      logger.warn(
        'OTP DEV FALLBACK enabled — /auth/otp/* returns 123456 for ANY phone. '
          + 'NEVER set MSG91_DEV_FALLBACK=true in production.',
      );
    } else if (env.msg91.authKey) {
      const widgetConfig = env.msg91.widgetId && env.msg91.widgetAuthToken
        ? ' + public widget config'
        : '';
      logger.info(`MSG91 OTP configured for widget access-token verification${widgetConfig}`);
    } else {
      logger.warn(
        'MSG91 OTP NOT configured — /auth/otp/msg91/verify will return 503. '
          + 'Missing in .env: MSG91_AUTH_KEY. Set MSG91_DEV_FALLBACK=true '
          + 'to use the dev OTP locally.',
      );
    }
  });
}

start().catch((err) => {
  logger.error('Failed to start server', err);
  process.exit(1);
});
