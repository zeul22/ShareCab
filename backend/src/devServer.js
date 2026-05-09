const fs = require('fs');
const path = require('path');
const { MongoMemoryServer } = require('mongodb-memory-server');

// Persistent data path so demo accounts and trips survive `npm run dev:e2e`
// restarts. Stored under the repo (gitignored), not in /tmp where macOS may
// prune. Override with MONGO_DATA_DIR if you want a different location.
const dbPath = process.env.MONGO_DATA_DIR
  || path.resolve(__dirname, '..', '.mongo-data');

(async () => {
  fs.mkdirSync(dbPath, { recursive: true });

  const mongo = await MongoMemoryServer.create({
    instance: {
      dbPath,
      storageEngine: 'wiredTiger', // wiredTiger persists; default ephemeralForTest does NOT
    },
  });
  process.env.MONGODB_URI = mongo.getUri();
  process.env.JWT_SECRET = process.env.JWT_SECRET || 'dev-only-insecure-secret';

  // eslint-disable-next-line no-console
  console.log(`[devServer] persistent MongoDB at ${process.env.MONGODB_URI}`);
  // eslint-disable-next-line no-console
  console.log(`[devServer] data dir: ${dbPath}`);

  require('./index');

  const shutdown = async () => {
    // eslint-disable-next-line no-console
    console.log('\n[devServer] stopping MongoDB (data persisted)');
    await mongo.stop({ doCleanup: false }); // keep the data dir on disk
    process.exit(0);
  };
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
})();
