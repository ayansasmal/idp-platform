'use strict';

const unleash = require('unleash-server');

const options = {
  db: {
    host: process.env.DATABASE_HOST || 'localhost',
    port: process.env.DATABASE_PORT || 5432,
    database: process.env.DATABASE_NAME || 'unleash',
    user: process.env.DATABASE_USER || 'unleash',
    password: process.env.DATABASE_PASSWORD || 'unleash',
    ssl: process.env.DATABASE_SSL === 'true' ? { rejectUnauthorized: false } : false,
  },
  server: {
    host: process.env.UNLEASH_HOST || '0.0.0.0',
    port: process.env.PORT || 4242,
    baseUriPath: process.env.BASE_URI_PATH || '',
    unleashUrl: process.env.UNLEASH_URL || 'http://localhost:4242',
    enableRequestLogger: true,
  },
  logLevel: process.env.LOG_LEVEL || 'info',
  enableOAS: true,
  versionCheck: {
    enable: false,
  },
  authentication: {
    type: 'open-source',
    customAuthHandler: process.env.AUTH_TYPE === 'custom' ? require('./custom-auth-handler') : undefined,
  },
  ui: {
    environment: process.env.NODE_ENV || 'production',
  },
};

// Initialize Unleash server
unleash.start(options).then((unleashInstance) => {
  console.log(`Unleash started on http://localhost:${options.server.port}${options.server.baseUriPath}`);
  console.log('Database host:', options.db.host);
  console.log('Database name:', options.db.database);
  
  // Graceful shutdown
  process.on('SIGINT', () => {
    console.log('Received SIGINT, shutting down gracefully...');
    unleashInstance.stop().then(() => {
      console.log('Unleash stopped');
      process.exit(0);
    }).catch((err) => {
      console.error('Error stopping Unleash:', err);
      process.exit(1);
    });
  });
}).catch((err) => {
  console.error('Failed to start Unleash:', err);
  process.exit(1);
});