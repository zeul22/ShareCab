const mongoose = require('mongoose');
const logger = require('../utils/logger');

async function connectDatabase() {
  const uri = process.env.MONGODB_URI;
  if (!uri) {
    logger.warn('MONGODB_URI is not set — running without a database connection.');
    return;
  }

  mongoose.set('strictQuery', true);

  try {
    await mongoose.connect(uri, { autoIndex: true });
    logger.info('Connected to MongoDB');
  } catch (err) {
    logger.error('MongoDB connection failed', err);
    throw err;
  }
}

module.exports = { connectDatabase };
