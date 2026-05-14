const { Pool } = require('pg');

const connectionString = process.env.DATABASE_URL || 'postgres://postgres:password@localhost:5432/love_companion';

const pool = new Pool({ connectionString });

module.exports = pool;
