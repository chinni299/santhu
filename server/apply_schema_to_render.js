/**
 * apply_schema_to_render.js
 * Render production database meeda schema.sql apply chestundi.
 * 
 * Usage:
 *   node apply_schema_to_render.js "postgres://user:pass@host/dbname"
 */

const { Pool } = require('pg');
const fs = require('fs');
const path = require('path');

const renderDbUrl = process.argv[2];

if (!renderDbUrl) {
  console.error('❌ Usage: node apply_schema_to_render.js "postgres://user:pass@host/dbname"');
  process.exit(1);
}

const pool = new Pool({
  connectionString: renderDbUrl,
  ssl: { rejectUnauthorized: false },  // Render SSL required
});

async function applySchema() {
  console.log('🔗 Connecting to Render production database...');
  const client = await pool.connect();

  try {
    const schemaPath = path.join(__dirname, 'schema.sql');
    if (!fs.existsSync(schemaPath)) {
      throw new Error('schema.sql not found!');
    }
    const schemaSql = fs.readFileSync(schemaPath, 'utf8');

    console.log('📋 Applying schema to Render DB...\n');

    // Split SQL by semicolon
    const rawStatements = schemaSql.split(';');

    let success = 0;
    let failed = 0;

    for (let rawStmt of rawStatements) {
      // Remove SQL single-line comments (-- ...)
      const cleanStmt = rawStmt
        .split('\n')
        .filter(line => !line.trim().startsWith('--'))
        .join('\n')
        .trim();

      if (!cleanStmt) continue;

      try {
        await client.query(cleanStmt);
        const match = cleanStmt.match(/(?:CREATE TABLE IF NOT EXISTS|CREATE SEQUENCE IF NOT EXISTS|CREATE INDEX IF NOT EXISTS)\s+(\w+)/i);
        if (match) {
          console.log(`  ✅ Created/Verified: ${match[1]}`);
        }
        success++;
      } catch (err) {
        if (err.message.includes('already exists')) {
          console.log(`  ℹ️ Already exists (skipped)`);
          success++;
        } else {
          console.error(`  ⚠️ Statement failed: ${err.message}`);
          console.error(`     SQL snippet: ${cleanStmt.substring(0, 100).replace(/\s+/g, ' ')}...`);
          failed++;
        }
      }
    }

    console.log(`\n📊 Schema application summary: ${success} OK, ${failed} failed`);

    // Verify tables
    const verifyRes = await client.query(`
      SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;
    `);
    const tables = verifyRes.rows.map(r => r.tablename);
    console.log(`\n✅ Tables currently in Render DB: ${tables.join(', ') || '(none)'}`);

    const expected = ['users', 'conversations', 'conversation_members', 'messages'];
    const missing = expected.filter(t => !tables.includes(t));
    if (missing.length === 0) {
      console.log('🎉 SUCCESS: All required tables exist in Render database!');
    } else {
      console.error(`❌ Missing tables: ${missing.join(', ')}`);
    }

  } finally {
    client.release();
    await pool.end();
  }
}

applySchema().catch(err => {
  console.error('❌ Fatal error:', err.message);
  process.exit(1);
});
