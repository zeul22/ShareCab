require('dotenv').config();
const http = require('http');
const app = require('./app');
const { connectDatabase } = require('./config/database');
const { attachSocketServer } = require('./sockets');
const logger = require('./utils/logger');

const PORT = process.env.PORT || 4000;

async function start() {
  await connectDatabase();

  const server = http.createServer(app);
  attachSocketServer(server);

  server.listen(PORT, () => {
    logger.info(`ShareCab API listening on http://localhost:${PORT}`);
  });
}

start().catch((err) => {
  logger.error('Failed to start server', err);
  process.exit(1);
});
