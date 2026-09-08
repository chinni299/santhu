require('dotenv').config();
const { Pool } = require('pg');
const p = new Pool({
  host: process.env.DB_HOST,
  port: process.env.DB_PORT,
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
});

async function check() {
  try {
    const r1 = await p.query("SELECT column_name FROM information_schema.columns WHERE table_name='conversations'");
    console.log('conversations cols:', r1.rows.map(x => x.column_name).join(', '));

    const r2 = await p.query("SELECT column_name FROM information_schema.columns WHERE table_name='conversation_members'");
    console.log('conv_members cols:', r2.rows.map(x => x.column_name).join(', '));

    const r3 = await p.query('SELECT id, email FROM users');
    console.log('users in DB:', JSON.stringify(r3.rows));

    const r4 = await p.query('SELECT * FROM conversation_members');
    console.log('conv_members rows:', JSON.stringify(r4.rows));

    const env1 = process.env.DUO_USER1_EMAIL || '(NOT SET)';
    const env2 = process.env.DUO_USER2_EMAIL || '(NOT SET)';
    console.log('DUO_USER1_EMAIL in .env:', env1);
    console.log('DUO_USER2_EMAIL in .env:', env2);
    console.log('JWT_SECRET set:', !!process.env.JWT_SECRET);
  } catch (e) {
    console.error('ERROR:', e.message);
  }
  process.exit(0);
}
check();
