const mongoose = require('mongoose');
const env = require('./env');
const logger = require('../utils/logger');

function redactUri(uri) {
  try {
    const parsed = new URL(uri);
    if (parsed.username) parsed.username = '***';
    if (parsed.password) parsed.password = '***';
    return parsed.toString();
  } catch {
    return '<redacted-mongodb-uri>';
  }
}

async function connectDatabase() {
  // env.mongoUri defaults to the docker-compose Mongo at localhost:27017/sharecab.
  // If the user hasn't run `docker compose up -d`, the connect call below will
  // throw with a clear ECONNREFUSED — better than silently running without a DB.
  const uri = env.mongoUri;
  const safeUri = redactUri(uri);

  mongoose.set('strictQuery', true);

  try {
    await mongoose.connect(uri, { autoIndex: true });
    logger.info(`Connected to MongoDB (${safeUri})`);
  } catch (err) {
    logger.error(
      `MongoDB connection failed at ${safeUri}.\n` +
      '  Is the database running? Start it with:\n' +
      '    docker compose up -d\n' +
      '  Or use the in-memory dev script:\n' +
      '    npm run dev:e2e',
    );
    throw err;
  }
}

module.exports = { connectDatabase };
