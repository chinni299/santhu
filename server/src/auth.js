const express = require("express");
const bcrypt = require("bcrypt");
const jwt = require("jsonwebtoken");

const pool = require("./db");
const { authenticateToken } = require("./middleware/authMiddleware");

const router = express.Router();

// ---------------------------------------------------------
// REGISTRATION IS COMPLETELY DISABLED FOR DUOCHAT
// DuoChat is a strict 2-user private application.
// Credentials must be provided via the server's .env file.
// ---------------------------------------------------------

// LOGIN (Strict 2-User Authentication)
router.post("/login", async (req, res) => {
  try {
    const { email, password } = req.body;

    if (!email || !password) {
      return res.status(400).json({
        success: false,
        message: "Email and password are required",
      });
    }

    const cleanEmail = email.trim().toLowerCase();
    
    const user1Email = (process.env.DUO_USER1_EMAIL || "").trim().toLowerCase();
    const user2Email = (process.env.DUO_USER2_EMAIL || "").trim().toLowerCase();

    // The backend must explicitly verify identity matching the .env secrets
    let targetId = null;
    let targetName = "";

    if (user1Email && cleanEmail === user1Email && password === process.env.DUO_USER1_PASSWORD) {
      targetId = 1;
      targetName = "User 1";
    } else if (user2Email && cleanEmail === user2Email && password === process.env.DUO_USER2_PASSWORD) {
      targetId = 2;
      targetName = "User 2";
    }

    if (!targetId) {
      console.warn(`[AUTH] Failed login attempt for email: ${cleanEmail}`);
      // Obfuscated generic error response
      return res.status(401).json({
        success: false,
        message: "Invalid email or password",
      });
    }

    if (!process.env.JWT_SECRET) {
      console.error("[AUTH ERROR] JWT_SECRET is missing from environment variables!");
      return res.status(500).json({ success: false, message: "Internal server configuration error" });
    }

    // Fetch the actual name from the database (preserves user-edited names)
    const userRow = await pool.query("SELECT name FROM users WHERE id = $1", [targetId]);
    const actualName = userRow.rows[0]?.name || targetName;

    const token = jwt.sign(
      {
        userId: targetId,
        email: cleanEmail,
      },
      process.env.JWT_SECRET,
      { expiresIn: "7d" }
    );

    console.log(`[AUTH] Successful login for User ${targetId} (name: ${actualName})`);

    res.json({
      success: true,
      message: "Login successful",
      user: {
        id: targetId,
        name: actualName,
        email: cleanEmail,
      },
      token,
    });
  } catch (error) {
    console.error("Login error:", error.message);

    res.status(500).json({
      success: false,
      message: "Login failed",
    });
  }
});

// UPDATE FCM TOKEN (Requires JWT Authentication)
router.post("/fcm-token", authenticateToken, async (req, res) => {
  try {
    const userId = req.user?.userId || req.user?.id;
    const { fcmToken } = req.body;

    if (!userId || !fcmToken) {
      return res.status(400).json({
        success: false,
        message: "fcmToken is required and user must be authenticated",
      });
    }

    await pool.query(
      "UPDATE users SET fcm_token = $1 WHERE id = $2",
      [fcmToken, userId]
    );

    console.log(`Updated FCM Token for user ${userId} ✅`);

    res.json({
      success: true,
      message: "FCM Token updated successfully",
    });
  } catch (error) {
    console.error("Update FCM token error:", error.message);

    res.status(500).json({
      success: false,
      message: "Failed to update FCM token",
    });
  }
});

// DB Migration for Public Key Column
pool.query(`
  ALTER TABLE users ADD COLUMN IF NOT EXISTS public_key TEXT;
`).then(() => {
  console.log("Users table public_key column verified ✅");
}).catch((err) => {
  console.error("Migration error for public_key column:", err.message);
});

// REGISTER PUBLIC KEY (Requires JWT Authentication)
router.post("/public-key", authenticateToken, async (req, res) => {
  try {
    const userId = req.user?.userId || req.user?.id;
    const { publicKey } = req.body;

    if (!userId || !publicKey) {
      return res.status(400).json({
        success: false,
        message: "publicKey is required",
      });
    }

    await pool.query(
      "UPDATE users SET public_key = $1 WHERE id = $2",
      [publicKey, userId]
    );

    console.log(`Registered X25519 Public Key for user ${userId} 🔑`);

    res.json({
      success: true,
      message: "Public key registered successfully",
      publicKey,
    });
  } catch (error) {
    console.error("Register public key error:", error.message);
    res.status(500).json({
      success: false,
      message: "Failed to register public key",
    });
  }
});

// FETCH PUBLIC KEY BY USER ID (Requires JWT Authentication)
router.get("/public-key/:userId", authenticateToken, async (req, res) => {
  try {
    const { userId } = req.params;

    const result = await pool.query(
      "SELECT id, name, public_key FROM users WHERE id = $1",
      [userId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: "User not found",
      });
    }

    const user = result.rows[0];

    res.json({
      success: true,
      userId: user.id,
      name: user.name,
      publicKey: user.public_key || null,
    });
  } catch (error) {
    console.error("Fetch public key error:", error.message);
    res.status(500).json({
      success: false,
      message: "Failed to fetch public key",
    });
  }
});

// COMPUTE SAFETY NUMBER (Requires JWT Authentication)
router.get("/safety-number/:conversationId", authenticateToken, async (req, res) => {
  try {
    const { conversationId } = req.params;
    const authUserId = req.user.id;

    // Verify conversation membership
    const memberCheck = await pool.query(
      "SELECT 1 FROM conversation_members WHERE conversation_id = $1 AND user_id = $2",
      [conversationId, authUserId]
    );
    if (memberCheck.rows.length === 0) {
      return res.status(403).json({ success: false, message: "Not authorized for this conversation" });
    }

    // Fetch public keys of both participants
    const keysRes = await pool.query(
      `SELECT u.id, u.public_key 
       FROM users u 
       JOIN conversation_members cm ON cm.user_id = u.id 
       WHERE cm.conversation_id = $1 
       ORDER BY u.id ASC`,
      [conversationId]
    );

    const keys = keysRes.rows.map((r) => r.public_key).filter(Boolean);
    if (keys.length < 2) {
      return res.json({
        success: true,
        safetyNumber: "Key Exchange Pending (Waiting for both users)",
      });
    }

    // Sort public keys deterministically
    keys.sort();
    const combined = keys.join(":");
    const crypto = require("crypto");
    const hash = crypto.createHash("sha256").update(combined).digest("hex");

    // Convert hex hash to 30-digit decimal number (6 blocks of 5 digits)
    let bigNum = BigInt("0x" + hash.substring(0, 32));
    let numStr = bigNum.toString().padEnd(30, "0").substring(0, 30);
    const blocks = numStr.match(/.{1,5}/g) || [];
    const formattedSafetyNumber = blocks.join(" ");

    res.json({
      success: true,
      conversationId: Number(conversationId),
      safetyNumber: formattedSafetyNumber,
    });
  } catch (error) {
    console.error("Compute safety number error:", error.message);
    res.status(500).json({ success: false, message: "Failed to compute safety number" });
  }
});

module.exports = router;