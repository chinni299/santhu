/**
 * extract_schema.js
 * Local PostgreSQL "duochat" DB nundi full schema extract chesi schema.sql ga save chestundi.
 * Run: node extract_schema.js
 */

require('dotenv').config();
const { Pool } = require('pg');
const fs = require('fs');

const pool = new Pool({
  host: process.env.DB_HOST || 'localhost',
  port: process.env.DB_PORT || 5432,
  database: process.env.DB_NAME || 'duochat',
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD || '2003',
});

async function extractSchema() {
  console.log('Connecting to local duochat database...');
  const client = await pool.connect();

  try {
    // 1. Get all tables in public schema
    const tablesRes = await client.query(`
      SELECT tablename FROM pg_tables
      WHERE schemaname = 'public'
      ORDER BY tablename;
    `);
    const tables = tablesRes.rows.map(r => r.tablename);
    console.log('Tables found:', tables);

    let sql = `-- ============================================
-- DuoChat Full Schema Export
-- Generated: ${new Date().toISOString()}
-- Source: localhost/duochat
-- Target: Render production database
-- ============================================\n\n`;

    // 2. Get sequences
    const seqRes = await client.query(`
      SELECT sequencename as sequence_name, start_value, increment_by, min_value, max_value
      FROM pg_sequences
      WHERE schemaname = 'public';
    `);
    if (seqRes.rows.length > 0) {
      sql += `-- SEQUENCES\n`;
      for (const seq of seqRes.rows) {
        sql += `CREATE SEQUENCE IF NOT EXISTS ${seq.sequence_name}
  START WITH ${seq.start_value}
  INCREMENT BY ${seq.increment_by}
  MINVALUE ${seq.min_value}
  MAXVALUE ${seq.max_value};\n\n`;
      }
    }

    // 3. For each table, get CREATE TABLE statement using pg_get_tabledef approach
    for (const table of tables) {
      sql += `-- TABLE: ${table}\n`;

      // Get columns with full type info
      const colRes = await client.query(`
        SELECT
          c.column_name,
          c.data_type,
          c.udt_name,
          c.character_maximum_length,
          c.numeric_precision,
          c.numeric_scale,
          c.column_default,
          c.is_nullable,
          c.ordinal_position
        FROM information_schema.columns c
        WHERE c.table_schema = 'public' AND c.table_name = $1
        ORDER BY c.ordinal_position;
      `, [table]);

      // Get primary key constraint
      const pkRes = await client.query(`
        SELECT kcu.column_name, tc.constraint_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
          ON tc.constraint_name = kcu.constraint_name
          AND tc.table_schema = kcu.table_schema
        WHERE tc.constraint_type = 'PRIMARY KEY'
          AND tc.table_schema = 'public'
          AND tc.table_name = $1
        ORDER BY kcu.ordinal_position;
      `, [table]);

      // Get unique constraints
      const uqRes = await client.query(`
        SELECT tc.constraint_name, kcu.column_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
          ON tc.constraint_name = kcu.constraint_name
        WHERE tc.constraint_type = 'UNIQUE'
          AND tc.table_schema = 'public'
          AND tc.table_name = $1;
      `, [table]);

      const pkCols = pkRes.rows.map(r => r.column_name);
      const uqMap = {};
      for (const r of uqRes.rows) {
        if (!uqMap[r.constraint_name]) uqMap[r.constraint_name] = [];
        uqMap[r.constraint_name].push(r.column_name);
      }

      sql += `CREATE TABLE IF NOT EXISTS ${table} (\n`;
      const colDefs = [];

      for (const col of colRes.rows) {
        let typeDef = '';

        // Handle serial/auto-increment (sequences)
        if (col.column_default && col.column_default.startsWith('nextval(')) {
          if (col.data_type === 'integer') typeDef = 'SERIAL';
          else if (col.data_type === 'bigint') typeDef = 'BIGSERIAL';
          else typeDef = 'SERIAL';
        } else if (col.data_type === 'character varying') {
          typeDef = col.character_maximum_length
            ? `VARCHAR(${col.character_maximum_length})`
            : 'TEXT';
        } else if (col.data_type === 'character') {
          typeDef = `CHAR(${col.character_maximum_length || 1})`;
        } else if (col.data_type === 'numeric') {
          if (col.numeric_precision && col.numeric_scale !== null) {
            typeDef = `NUMERIC(${col.numeric_precision},${col.numeric_scale})`;
          } else {
            typeDef = 'NUMERIC';
          }
        } else if (col.data_type === 'ARRAY') {
          typeDef = col.udt_name.replace('_', '') + '[]';
        } else if (col.data_type === 'USER-DEFINED') {
          typeDef = col.udt_name;
        } else {
          typeDef = col.data_type.toUpperCase();
        }

        let colDef = `  ${col.column_name} ${typeDef}`;
        if (col.is_nullable === 'NO' && !col.column_default?.startsWith('nextval(')) {
          colDef += ' NOT NULL';
        }
        if (col.column_default && !col.column_default.startsWith('nextval(')) {
          colDef += ` DEFAULT ${col.column_default}`;
        }
        colDefs.push(colDef);
      }

      // Add PRIMARY KEY
      if (pkCols.length > 0) {
        colDefs.push(`  PRIMARY KEY (${pkCols.join(', ')})`);
      }

      // Add UNIQUE constraints
      for (const [cname, cols] of Object.entries(uqMap)) {
        colDefs.push(`  UNIQUE (${cols.join(', ')})`);
      }

      sql += colDefs.join(',\n') + '\n);\n\n';

      // Get check constraints
      const checkRes = await client.query(`
        SELECT cc.constraint_name, cc.check_clause
        FROM information_schema.check_constraints cc
        JOIN information_schema.table_constraints tc
          ON cc.constraint_name = tc.constraint_name
        WHERE tc.table_schema = 'public' AND tc.table_name = $1;
      `, [table]);
      for (const ch of checkRes.rows) {
        sql += `ALTER TABLE ${table} ADD CONSTRAINT IF NOT EXISTS ${ch.constraint_name} CHECK (${ch.check_clause});\n`;
      }
    }

    // 4. Foreign keys (after all tables created)
    sql += `\n-- FOREIGN KEYS\n`;
    const fkRes = await client.query(`
      SELECT
        tc.table_name,
        tc.constraint_name,
        kcu.column_name,
        ccu.table_name AS foreign_table_name,
        ccu.column_name AS foreign_column_name,
        rc.delete_rule,
        rc.update_rule
      FROM information_schema.table_constraints tc
      JOIN information_schema.key_column_usage kcu
        ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
      JOIN information_schema.constraint_column_usage ccu
        ON ccu.constraint_name = tc.constraint_name AND ccu.table_schema = tc.table_schema
      JOIN information_schema.referential_constraints rc
        ON tc.constraint_name = rc.constraint_name
      WHERE tc.constraint_type = 'FOREIGN KEY' AND tc.table_schema = 'public';
    `);

    for (const fk of fkRes.rows) {
      sql += `ALTER TABLE ${fk.table_name} ADD CONSTRAINT IF NOT EXISTS ${fk.constraint_name}
  FOREIGN KEY (${fk.column_name}) REFERENCES ${fk.foreign_table_name}(${fk.foreign_column_name})`;
      if (fk.delete_rule && fk.delete_rule !== 'NO ACTION') sql += ` ON DELETE ${fk.delete_rule}`;
      if (fk.update_rule && fk.update_rule !== 'NO ACTION') sql += ` ON UPDATE ${fk.update_rule}`;
      sql += `;\n`;
    }

    // 5. Indexes (excluding PK/unique which are already created)
    sql += `\n-- INDEXES\n`;
    const idxRes = await client.query(`
      SELECT
        i.relname AS index_name,
        t.relname AS table_name,
        ix.indisunique AS is_unique,
        array_agg(a.attname ORDER BY array_position(ix.indkey, a.attnum)) AS columns
      FROM pg_class t
      JOIN pg_index ix ON t.oid = ix.indrelid
      JOIN pg_class i ON i.oid = ix.indexrelid
      JOIN pg_namespace n ON t.relnamespace = n.oid
      JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = ANY(ix.indkey)
      WHERE n.nspname = 'public'
        AND t.relkind = 'r'
        AND NOT ix.indisprimary
        AND NOT EXISTS (
          SELECT 1 FROM information_schema.table_constraints tc
          WHERE tc.constraint_name = i.relname
            AND tc.constraint_type IN ('UNIQUE', 'PRIMARY KEY')
        )
      GROUP BY i.relname, t.relname, ix.indisunique
      ORDER BY t.relname, i.relname;
    `);

    for (const idx of idxRes.rows) {
      const cols = idx.columns.join(', ');
      const unique = idx.is_unique ? 'UNIQUE ' : '';
      sql += `CREATE ${unique}INDEX IF NOT EXISTS ${idx.index_name} ON ${idx.table_name} (${cols});\n`;
    }

    // Write to file
    const outputPath = './schema.sql';
    fs.writeFileSync(outputPath, sql, 'utf8');
    console.log(`\n✅ Schema exported to ${outputPath}`);
    console.log(`   Tables: ${tables.join(', ')}`);
    console.log(`   Size: ${(sql.length / 1024).toFixed(1)} KB`);

  } finally {
    client.release();
    await pool.end();
  }
}

extractSchema().catch(err => {
  console.error('❌ Error:', err.message);
  process.exit(1);
});
