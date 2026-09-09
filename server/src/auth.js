require("dotenv").config();
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
    const cleanPassword = (password || "").trim();
    
    const user1Email = (process.env.DUO_USER1_EMAIL || "").trim().toLowerCase();
    const user2Email = (process.env.DUO_USER2_EMAIL || "").trim().toLowerCase();
    const user1Pass = (process.env.DUO_USER1_PASSWORD || "").trim();
    const user2Pass = (process.env.DUO_USER2_PASSWORD || "").trim();

    // The backend must explicitly verify identity matching the .env secrets
    let targetId = null;
    let targetName = "";

    if (user1Email && cleanEmail === user1Email && cleanPassword === user1Pass) {
      targetId = 1;
      targetName = "User 1";
    } else if (user2Email && cleanEmail === user2Email && cleanPassword === user2Pass) {
      targetId = 2;
      targetName = "User 2";
    }

    if (!targetId) {
      console.warn(`[AUTH] Failed login attempt for email: "${cleanEmail}" (pass len: ${cleanPassword.length}). Expected User1: "${user1Email}" (pass len: ${user1Pass.length}), User2: "${user2Email}" (pass len: ${user2Pass.length})`);
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

// AVATAR UPLOAD STORAGE & CONFIG
const multer = require("multer");
const path = require("path");
const fs = require("fs");
const crypto = require("crypto");

const uploadsDir = path.join(__dirname, "../uploads");
if (!fs.existsSync(uploadsDir)) {
  fs.mkdirSync(uploadsDir, { recursive: true });
}

const avatarStorage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, uploadsDir);
  },
  filename: (req, file, cb) => {
    const originalExt = path.extname(file.originalname).toLowerCase().replace(/[^a-z0-9.]/g, "") || ".jpg";
    const uniqueFilename = `avatar_${req.user?.userId || req.user?.id || Date.now()}_${crypto.randomUUID()}${originalExt}`;
    cb(null, uniqueFilename);
  },
});

const avatarUpload = multer({
  storage: avatarStorage,
  limits: { fileSize: 10 * 1024 * 1024 }, // 10 MB limit
  fileFilter: (req, file, cb) => {
    const ext = path.extname(file.originalname).toLowerCase();
    if ([".jpg", ".jpeg", ".png", ".webp", ".gif"].includes(ext)) {
      cb(null, true);
    } else {
      cb(new Error("Only image files are allowed for avatars"), false);
    }
  },
});

// UPLOAD USER AVATAR (Requires JWT Authentication)
router.post("/avatar", authenticateToken, (req, res) => {
  avatarUpload.single("avatar")(req, res, async (err) => {
    if (err) {
      return res.status(400).json({ success: false, message: err.message || "Avatar upload failed" });
    }
    if (!req.file) {
      return res.status(400).json({ success: false, message: "No avatar image provided" });
    }

    try {
      const authUserId = req.user?.userId || req.user?.id;
      const avatarFilename = req.file.filename;
      const avatarUrl = `/auth/avatar/${authUserId}?t=${Date.now()}`;

      await pool.query(
        "UPDATE users SET avatar_url = $1 WHERE id = $2",
        [avatarFilename, authUserId]
      );

      console.log(`[AVATAR] Uploaded and saved avatar for user ${authUserId}: ${avatarFilename} ✅`);

      res.json({
        success: true,
        message: "Avatar uploaded successfully",
        avatar_url: avatarUrl,
        filename: avatarFilename,
      });
    } catch (error) {
      console.error("Save avatar error:", error.message);
      res.status(500).json({ success: false, message: "Failed to save avatar" });
    }
  });
});

// GET USER AVATAR (Serves image file directly)
router.get("/avatar/:userId", async (req, res) => {
  try {
    const { userId } = req.params;
    const userRes = await pool.query(
      "SELECT avatar_url FROM users WHERE id = $1",
      [userId]
    );

    if (userRes.rows.length === 0 || !userRes.rows[0].avatar_url) {
      return res.status(404).json({ success: false, message: "No avatar set" });
    }

    const storedVal = userRes.rows[0].avatar_url;
    const safeFilename = path.basename(storedVal).replace(/[^a-zA-Z0-9.\-_]/g, "");
    const filePath = path.join(uploadsDir, safeFilename);

    if (!fs.existsSync(filePath)) {
      return res.status(404).json({ success: false, message: "Avatar file not found on disk" });
    }

    const ext = path.extname(safeFilename).toLowerCase();
    const mimeTypes = {
      ".jpg": "image/jpeg",
      ".jpeg": "image/jpeg",
      ".png": "image/png",
      ".webp": "image/webp",
      ".gif": "image/gif",
    };

    res.setHeader("Content-Type", mimeTypes[ext] || "image/jpeg");
    res.setHeader("Cache-Control", "public, max-age=86400");
    const stream = fs.createReadStream(filePath);
    stream.pipe(res);
  } catch (error) {
    console.error("Get avatar error:", error.message);
    res.status(500).json({ success: false, message: "Failed to retrieve avatar" });
  }
});

// GET USER PROFILE
router.get("/profile/:userId", async (req, res) => {
  try {
    const { userId } = req.params;
    const userRes = await pool.query(
      "SELECT id, name, email, avatar_url, status, is_online, last_seen_at FROM users WHERE id = $1",
      [userId]
    );

    if (userRes.rows.length === 0) {
      return res.status(404).json({ success: false, message: "User not found" });
    }

    const user = userRes.rows[0];
    if (user.avatar_url) {
      user.avatar_url = `/auth/avatar/${user.id}`;
    }

    res.json({
      success: true,
      user,
    });
  } catch (error) {
    console.error("Get profile error:", error.message);
    res.status(500).json({ success: false, message: "Failed to fetch profile" });
  }
});

// UPDATE USER PROFILE
router.put("/profile", authenticateToken, async (req, res) => {
  try {
    const authUserId = req.user?.userId || req.user?.id;
    const { name, status, avatar_url } = req.body;

    if (!authUserId) {
      return res.status(401).json({ success: false, message: "Unauthorized" });
    }

    const updates = [];
    const values = [];
    let paramIndex = 1;

    if (name !== undefined && name !== null && name.trim().length > 0) {
      updates.push(`name = $${paramIndex++}`);
      values.push(name.trim());
    }

    if (status !== undefined && status !== null) {
      updates.push(`status = $${paramIndex++}`);
      values.push(status.trim());
    }

    if (avatar_url !== undefined && avatar_url !== null) {
      updates.push(`avatar_url = $${paramIndex++}`);
      values.push(avatar_url.trim());
    }

    if (updates.length === 0) {
      return res.status(400).json({ success: false, message: "No profile fields to update" });
    }

    values.push(authUserId);
    const query = `UPDATE users SET ${updates.join(", ")} WHERE id = $${paramIndex} RETURNING id, name, email, avatar_url, status, is_online, last_seen_at`;
    
    const result = await pool.query(query, values);
    const updatedUser = result.rows[0];

    console.log(`[PROFILE] Updated profile for user ${authUserId}: name="${updatedUser.name}", avatar_url=${updatedUser.avatar_url ? 'SET' : 'NONE'}`);

    res.json({
      success: true,
      message: "Profile updated successfully",
      user: updatedUser,
    });
  } catch (error) {
    console.error("Update profile error:", error.message);
    res.status(500).json({ success: false, message: "Failed to update profile" });
  }
});

module.exports = router;