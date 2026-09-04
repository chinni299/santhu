require("dotenv").config();
const pool = require("./db");

async function migrate() {
  try {
    await pool.query(`
      ALTER TABLE messages 
      ADD COLUMN IF NOT EXISTS reactions JSONB DEFAULT '{}'::jsonb;
    `);
    console.log("Successfully added reactions column to messages table ✅");
  } catch (err) {
    console.error("Migration error:", err.message);
  } finally {
    process.exit(0);
  }
}

migrate();
