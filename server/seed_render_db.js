require('dotenv').config();
const { Pool } = require('pg');

const renderDbUrl = "postgresql://santhu_user:bp0B3whCXmmcZ5mq1vHGYShVeDyaFRqY@dpg-daggb1mq1p3s73b9s1gg-a.oregon-postgres.render.com/santhu";

const pool = new Pool({
  connectionString: renderDbUrl,
  ssl: { rejectUnauthorized: false },
});

async function seed() {
  const email1 = (process.env.DUO_USER1_EMAIL || "pottoda65@gmail.com").trim().toLowerCase();
  const email2 = (process.env.DUO_USER2_EMAIL || "pottiamma45@gmail.com").trim().toLowerCase();

  console.log("🌱 Seeding Render DB with User 1 and User 2...");
  console.log(`User 1 Email: ${email1}`);
  console.log(`User 2 Email: ${email2}`);

  try {
    await pool.query(
      `INSERT INTO users (id, name, email, password_hash)
       VALUES (1, 'User 1', $1, 'LOCKED_NO_LOGIN')
       ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email`,
      [email1]
    );
    console.log("✅ User 1 seeded.");

    await pool.query(
      `INSERT INTO users (id, name, email, password_hash)
       VALUES (2, 'User 2', $1, 'LOCKED_NO_LOGIN')
       ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email`,
      [email2]
    );
    console.log("✅ User 2 seeded.");

    await pool.query(
      `INSERT INTO conversations (id) VALUES (1) ON CONFLICT (id) DO NOTHING`
    );
    console.log("✅ Conversation 1 seeded.");

    await pool.query(
      `INSERT INTO conversation_members (conversation_id, user_id) VALUES (1, 1) ON CONFLICT DO NOTHING`
    );
    await pool.query(
      `INSERT INTO conversation_members (conversation_id, user_id) VALUES (1, 2) ON CONFLICT DO NOTHING`
    );
    console.log("✅ Conversation members seeded.");

    const resUsers = await pool.query("SELECT id, name, email FROM users ORDER BY id");
    console.log("📋 Users in DB:", resUsers.rows);

    const resConvs = await pool.query("SELECT * FROM conversations");
    console.log("📋 Conversations in DB:", resConvs.rows);

    const resMembers = await pool.query("SELECT * FROM conversation_members");
    console.log("📋 Members in DB:", resMembers.rows);

  } catch (err) {
    console.error("❌ Seed error:", err.message);
  } finally {
    await pool.end();
  }
}

seed();
