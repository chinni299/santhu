const express = require("express");
const pool = require("./db");
const multer = require("multer");
const path = require("path");
const fs = require("fs");
const crypto = require("crypto");
const { authenticateToken } = require("./middleware/authMiddleware");

console.log("MESSAGES ROUTE LOADED ✅");

const router = express.Router();
router.use(authenticateToken);

const uploadsDir = path.join(__dirname, "../uploads");
if (!fs.existsSync(uploadsDir)) {
  fs.mkdirSync(uploadsDir, { recursive: true });
}

// File extension Whitelist and Blacklist
const ALLOWED_EXTENSIONS = new Set([
  // Images
  ".jpg", ".jpeg", ".png", ".webp", ".gif",
  // Documents
  ".pdf", ".txt", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx",
  // Audio (voice messages)
  ".m4a", ".mp3", ".wav", ".aac", ".ogg", ".webm",
  // Encrypted binary
  ".bin"
]);

// Migration for E2EE columns
pool.query(`
  ALTER TABLE messages ADD COLUMN IF NOT EXISTS nonce TEXT;
  ALTER TABLE messages ADD COLUMN IF NOT EXISTS is_encrypted BOOLEAN DEFAULT true;
`).then(() => {
  console.log("Messages table nonce and is_encrypted columns verified ✅");
}).catch((err) => {
  console.error("Migration error for messages E2EE columns:", err.message);
});

// Migration for Disappearing Messages
pool.query(`
  ALTER TABLE messages ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;
  ALTER TABLE conversations ADD COLUMN IF NOT EXISTS disappearing_timer_seconds INTEGER;
`).then(() => {
  console.log("Disappearing-messages columns (expires_at, disappearing_timer_seconds) verified ✅");
}).catch((err) => {
  console.error("Migration error for disappearing-messages columns:", err.message);
});

// Migration for Pinned Messages
pool.query(`
  ALTER TABLE messages ADD COLUMN IF NOT EXISTS is_pinned BOOLEAN DEFAULT false;
  ALTER TABLE messages ADD COLUMN IF NOT EXISTS pinned_by INTEGER;
  ALTER TABLE messages ADD COLUMN IF NOT EXISTS pinned_at TIMESTAMPTZ;
`).then(() => {
  console.log("Pinned-messages columns (is_pinned, pinned_by, pinned_at) verified ✅");
}).catch((err) => {
  console.error("Migration error for pinned-messages columns:", err.message);
});

// Migration for Live Location Sharing
pool.query(`
  ALTER TABLE messages ADD COLUMN IF NOT EXISTS live_location_active BOOLEAN DEFAULT false;
  ALTER TABLE messages ADD COLUMN IF NOT EXISTS live_location_expires_at TIMESTAMPTZ;
`).then(() => {
  console.log("Live-location columns (live_location_active, live_location_expires_at) verified ✅");
}).catch((err) => {
  console.error("Migration error for live-location columns:", err.message);
});

// Migration for Couple Status & Moods
pool.query(`
  CREATE TABLE IF NOT EXISTS couple_user_status (
    user_id INTEGER PRIMARY KEY,
    status VARCHAR(32) NOT NULL DEFAULT 'online',
    custom_text TEXT,
    updated_at TIMESTAMPTZ DEFAULT NOW()
  );
  CREATE TABLE IF NOT EXISTS user_moods (
    user_id INTEGER PRIMARY KEY,
    mood VARCHAR(32),
    updated_at TIMESTAMPTZ DEFAULT NOW()
  );
  CREATE TABLE IF NOT EXISTS important_dates (
    id SERIAL PRIMARY KEY,
    title TEXT NOT NULL,
    date_type VARCHAR(32) NOT NULL DEFAULT 'custom',
    date_value TIMESTAMPTZ NOT NULL,
    note TEXT,
    created_by INTEGER NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
  );
  CREATE TABLE IF NOT EXISTS daily_questions (
    id SERIAL PRIMARY KEY,
    question_text TEXT NOT NULL,
    question_date DATE UNIQUE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
  );
  CREATE TABLE IF NOT EXISTS daily_question_answers (
    id SERIAL PRIMARY KEY,
    question_id INTEGER REFERENCES daily_questions(id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL,
    answer_text TEXT NOT NULL,
    answered_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(question_id, user_id)
  );
  CREATE TABLE IF NOT EXISTS private_memories (
    id SERIAL PRIMARY KEY,
    type VARCHAR(16) NOT NULL DEFAULT 'photo',
    media_url TEXT NOT NULL,
    caption TEXT,
    memory_date TIMESTAMPTZ NOT NULL,
    created_by INTEGER NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
  );
  CREATE TABLE IF NOT EXISTS shared_notes (
    id SERIAL PRIMARY KEY,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    created_by INTEGER NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
  );
  CREATE TABLE IF NOT EXISTS couple_routines (
    user_id INTEGER PRIMARY KEY,
    morning_enabled BOOLEAN DEFAULT false,
    morning_time VARCHAR(8) DEFAULT '08:00',
    night_enabled BOOLEAN DEFAULT false,
    night_time VARCHAR(8) DEFAULT '22:00',
    custom_morning_msg TEXT,
    custom_night_msg TEXT,
    sound_enabled BOOLEAN DEFAULT true,
    updated_at TIMESTAMPTZ DEFAULT NOW()
  );
`).then(() => {
  console.log("Couple-status & user-moods tables verified ✅");
}).catch((err) => {
  console.error("Migration error for couple-status/user-moods:", err.message);
});

const DANGEROUS_EXTENSIONS = new Set([
  ".exe", ".bat", ".cmd", ".sh", ".js", ".apk", ".msi", ".vbs", ".ps1", ".php", ".py", ".pl", ".cgi", ".jar", ".scr", ".com", ".pif", ".htm", ".html"
]);

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, uploadsDir);
  },
  filename: (req, file, cb) => {
    const originalExt = path.extname(file.originalname).toLowerCase().replace(/[^a-z0-9.]/g, "");
    const safeExt = ALLOWED_EXTENSIONS.has(originalExt) ? originalExt : ".bin";
    const uniqueFilename = `${crypto.randomUUID()}${safeExt}`;
    cb(null, uniqueFilename);
  },
});

const fileFilter = (req, file, cb) => {
  const ext = path.extname(file.originalname).toLowerCase();
  
  if (DANGEROUS_EXTENSIONS.has(ext) || !ALLOWED_EXTENSIONS.has(ext)) {
    const error = new Error("UNSUPPORTED_FILE_TYPE");
    error.code = "UNSUPPORTED_FILE_TYPE";
    return cb(error, false);
  }
  
  cb(null, true);
};

const upload = multer({
  storage,
  limits: { fileSize: 25 * 1024 * 1024 }, // 25 MB Limit
  fileFilter,
});

const uploadSingleFile = (req, res, next) => {
  upload.single("file")(req, res, (err) => {
    if (err) {
      if (err.code === "LIMIT_FILE_SIZE") {
        return res.status(413).json({
          success: false,
          message: "Attachment too large. Maximum size is 25 MB.",
        });
      }
      if (err.code === "UNSUPPORTED_FILE_TYPE" || err.message === "UNSUPPORTED_FILE_TYPE") {
        return res.status(415).json({
          success: false,
          message: "Unsupported file type. Executable and script files are not allowed.",
        });
      }
      return res.status(400).json({
        success: false,
        message: err.message || "File upload failed.",
      });
    }
    next();
  });
};

// GET TEST ROUTE (Verify router mounting)
router.get("/test", (req, res) => {
  res.json({
    success: true,
    message: "Messages router is mounted correctly ✅",
  });
});

// GET SECURE PRIVATE ATTACHMENT BY MESSAGE ID
router.get("/attachments/:messageId", async (req, res) => {
  try {
    const { messageId } = req.params;
    const authUserId = req.user.id;

    // 1. Fetch message and attachment info
    const msgRes = await pool.query(
      `SELECT m.id, m.conversation_id, m.attachment_url, m.attachment_type, m.attachment_name, m.is_deleted
       FROM messages m
       WHERE m.id = $1`,
      [messageId]
    );

    if (msgRes.rows.length === 0) {
      return res.status(404).json({ success: false, message: "Attachment unavailable" });
    }

    const msg = msgRes.rows[0];

    if (msg.is_deleted || !msg.attachment_url) {
      return res.status(404).json({ success: false, message: "Attachment unavailable" });
    }

    // 2. Verify conversation authorization for req.user.id
    const memberCheck = await pool.query(
      `SELECT 1 FROM conversation_members WHERE conversation_id = $1 AND user_id = $2`,
      [msg.conversation_id, authUserId]
    );

    if (memberCheck.rows.length === 0) {
      return res.status(403).json({ success: false, message: "Not authorized to access this attachment" });
    }

    // 3. Extract filename from attachment_url safely
    const storedFilename = path.basename(msg.attachment_url);
    const safeFilename = path.basename(storedFilename).replace(/[^a-zA-Z0-9.\-_]/g, "");
    const filePath = path.join(uploadsDir, safeFilename);

    if (!fs.existsSync(filePath)) {
      return res.status(404).json({ success: false, message: "Attachment unavailable" });
    }

    // 4. Set Content-Type and Disposition
    const ext = path.extname(safeFilename).toLowerCase();
    const mimeTypes = {
      ".jpg": "image/jpeg",
      ".jpeg": "image/jpeg",
      ".png": "image/png",
      ".webp": "image/webp",
      ".gif": "image/gif",
      ".pdf": "application/pdf",
      ".txt": "text/plain",
      ".doc": "application/msword",
      ".docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
      ".xls": "application/vnd.ms-excel",
      ".xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      ".ppt": "application/vnd.ms-powerpoint",
      ".pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
      ".m4a": "audio/mp4",
      ".mp3": "audio/mpeg",
      ".wav": "audio/wav",
      ".aac": "audio/aac",
      ".ogg": "audio/ogg",
      ".webm": "audio/webm",
    };

    const contentType = mimeTypes[ext] || "application/octet-stream";
    const disposition = (msg.attachment_type === "image" || msg.attachment_type === "audio")
      ? "inline"
      : `attachment; filename="${encodeURIComponent(msg.attachment_name || safeFilename)}"`;

    res.setHeader("Content-Type", contentType);
    res.setHeader("Content-Disposition", disposition);
    res.setHeader("Cache-Control", "private, no-cache, no-store, must-revalidate");

    const stream = fs.createReadStream(filePath);
    stream.pipe(res);
  } catch (error) {
    console.error("Secure attachment download error:", error.message);
    res.status(500).json({ success: false, message: "Internal server error" });
  }
});

// GET SECURE PRIVATE ATTACHMENT BY FILENAME
router.get("/attachments/file/:filename", async (req, res) => {
  try {
    const { filename } = req.params;
    const authUserId = req.user.id;

    // Prevent path traversal
    const safeFilename = path.basename(filename).replace(/[^a-zA-Z0-9.\-_]/g, "");

    // Find corresponding message and conversation
    const msgRes = await pool.query(
      `SELECT m.id, m.conversation_id, m.attachment_type, m.attachment_name, m.is_deleted
       FROM messages m
       WHERE m.attachment_url LIKE $1`,
      [`%${safeFilename}`]
    );

    if (msgRes.rows.length === 0) {
      return res.status(404).json({ success: false, message: "Attachment unavailable" });
    }

    const msg = msgRes.rows[0];

    if (msg.is_deleted) {
      return res.status(404).json({ success: false, message: "Attachment unavailable" });
    }

    // Verify conversation authorization for req.user.id
    const memberCheck = await pool.query(
      `SELECT 1 FROM conversation_members WHERE conversation_id = $1 AND user_id = $2`,
      [msg.conversation_id, authUserId]
    );

    if (memberCheck.rows.length === 0) {
      return res.status(403).json({ success: false, message: "Not authorized to access this attachment" });
    }

    const filePath = path.join(uploadsDir, safeFilename);

    if (!fs.existsSync(filePath)) {
      return res.status(404).json({ success: false, message: "Attachment unavailable" });
    }

    const ext = path.extname(safeFilename).toLowerCase();
    const mimeTypes = {
      ".jpg": "image/jpeg",
      ".jpeg": "image/jpeg",
      ".png": "image/png",
      ".webp": "image/webp",
      ".gif": "image/gif",
      ".pdf": "application/pdf",
      ".txt": "text/plain",
      ".doc": "application/msword",
      ".docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
      ".xls": "application/vnd.ms-excel",
      ".xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      ".ppt": "application/vnd.ms-powerpoint",
      ".pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
      ".m4a": "audio/mp4",
      ".mp3": "audio/mpeg",
      ".wav": "audio/wav",
      ".aac": "audio/aac",
      ".ogg": "audio/ogg",
      ".webm": "audio/webm",
    };

    const contentType = mimeTypes[ext] || "application/octet-stream";
    const disposition = (msg.attachment_type === "image" || msg.attachment_type === "audio")
      ? "inline"
      : `attachment; filename="${encodeURIComponent(msg.attachment_name || safeFilename)}"`;

    res.setHeader("Content-Type", contentType);
    res.setHeader("Content-Disposition", disposition);
    res.setHeader("Cache-Control", "private, no-cache, no-store, must-revalidate");

    const stream = fs.createReadStream(filePath);
    stream.pipe(res);
  } catch (error) {
    console.error("Secure attachment download error:", error.message);
    res.status(500).json({ success: false, message: "Internal server error" });
  }
});

// GET UNREAD MESSAGE COUNT FOR A CONVERSATION AND USER
router.get("/unread-count/:conversationId/:userId", async (req, res) => {
  try {
    const { conversationId, userId } = req.params;

    const result = await pool.query(
      `SELECT COUNT(*)::int AS unread_count
       FROM messages
       WHERE conversation_id = $1 AND sender_id != $2 AND is_read = false`,
      [conversationId, userId]
    );

    const unreadCount = parseInt(result.rows[0].unread_count || 0, 10);
    console.log(
      `Fetched unread count for conversation ${conversationId}, user ${userId}: ${unreadCount}`
    );

    res.json({
      success: true,
      unreadCount,
    });
  } catch (error) {
    console.error("Get unread count error:", error.message);
    res.status(500).json({
      success: false,
      message: "Failed to fetch unread count",
    });
  }
});

// GET CONVERSATIONS FOR USER
router.get("/conversations/:userId", async (req, res) => {
  try {
    const { userId } = req.params;

    let result = await pool.query(
      `SELECT 
        c.id AS conversation_id,
        other_u.id AS other_user_id,
        other_u.name AS other_user_name,
        other_u.email AS other_user_email,
        other_u.avatar_url AS other_user_avatar,
        CASE 
          WHEN latest_m.is_deleted = true THEN 'This message was deleted' 
          WHEN latest_m.attachment_type = 'image' THEN '📷 Photo'
          WHEN latest_m.attachment_type = 'audio' THEN '🎤 Voice message'
          WHEN latest_m.attachment_type = 'location' THEN '📍 Location'
          WHEN latest_m.attachment_type IS NOT NULL THEN '📎 File'
          ELSE latest_m.message 
        END AS last_message,
        latest_m.created_at AS last_message_time,
        COALESCE(unread_m.unread_count, 0)::int AS unread_count
      FROM conversation_members cm
      JOIN conversations c ON c.id = cm.conversation_id
      JOIN conversation_members other_cm ON other_cm.conversation_id = c.id AND other_cm.user_id != cm.user_id
      JOIN users other_u ON other_u.id = other_cm.user_id
      LEFT JOIN LATERAL (
        SELECT message, attachment_type, is_deleted, created_at
        FROM messages
        WHERE conversation_id = c.id
        ORDER BY created_at DESC
        LIMIT 1
      ) latest_m ON true
      LEFT JOIN LATERAL (
        SELECT COUNT(*)::int AS unread_count
        FROM messages
        WHERE conversation_id = c.id AND sender_id != cm.user_id AND is_read = false
      ) unread_m ON true
      WHERE cm.user_id = $1
      ORDER BY COALESCE(latest_m.created_at, c.created_at) DESC`,
      [userId]
    );

    if (result.rows.length === 0) {
      // Auto-ensure private 2-user conversation exists
      await pool.query("INSERT INTO conversations (id) VALUES (1) ON CONFLICT (id) DO NOTHING");
      await pool.query("INSERT INTO conversation_members (conversation_id, user_id) VALUES (1, 1) ON CONFLICT DO NOTHING");
      await pool.query("INSERT INTO conversation_members (conversation_id, user_id) VALUES (1, 2) ON CONFLICT DO NOTHING");

      result = await pool.query(
        `SELECT 
          c.id AS conversation_id,
          other_u.id AS other_user_id,
          other_u.name AS other_user_name,
          other_u.email AS other_user_email,
          other_u.avatar_url AS other_user_avatar,
          CASE 
            WHEN latest_m.is_deleted = true THEN 'This message was deleted' 
            WHEN latest_m.attachment_type = 'image' THEN '📷 Photo'
            WHEN latest_m.attachment_type = 'audio' THEN '🎤 Voice message'
          WHEN latest_m.attachment_type = 'location' THEN '📍 Location'
            WHEN latest_m.attachment_type IS NOT NULL THEN '📎 File'
            ELSE latest_m.message 
          END AS last_message,
          latest_m.created_at AS last_message_time,
          COALESCE(unread_m.unread_count, 0)::int AS unread_count
        FROM conversation_members cm
        JOIN conversations c ON c.id = cm.conversation_id
        JOIN conversation_members other_cm ON other_cm.conversation_id = c.id AND other_cm.user_id != cm.user_id
        JOIN users other_u ON other_u.id = other_cm.user_id
        LEFT JOIN LATERAL (
          SELECT message, attachment_type, is_deleted, created_at
          FROM messages
          WHERE conversation_id = c.id
          ORDER BY created_at DESC
          LIMIT 1
        ) latest_m ON true
        LEFT JOIN LATERAL (
          SELECT COUNT(*)::int AS unread_count
          FROM messages
          WHERE conversation_id = c.id AND sender_id != cm.user_id AND is_read = false
        ) unread_m ON true
        WHERE cm.user_id = $1
        ORDER BY COALESCE(latest_m.created_at, c.created_at) DESC`,
        [userId]
      );
    }

    console.log(`Fetched ${result.rows.length} conversations for user ${userId} ✅`);

    res.json({
      success: true,
      data: result.rows,
    });
  } catch (error) {
    console.error("Get conversations error:", error.message);
    res.status(500).json({
      success: false,
      message: "Failed to fetch conversations",
    });
  }
});

// GET MESSAGES BY CONVERSATION ID
router.get("/:conversationId", async (req, res) => {
  try {
    const { conversationId } = req.params;
    const authUserId = req.user.id;

    // Verify conversation authorization
    const memberCheck = await pool.query(
      `SELECT 1 FROM conversation_members WHERE conversation_id = $1 AND user_id = $2`,
      [conversationId, authUserId]
    );

    if (memberCheck.rows.length === 0) {
      return res.status(403).json({ success: false, message: "Not authorized to access messages in this conversation" });
    }

    const result = await pool.query(
      `SELECT 
        m.id, m.conversation_id, m.sender_id, m.message, 
        m.attachment_url, m.attachment_type, m.attachment_name, m.attachment_size,
        m.nonce, m.is_encrypted,
        m.is_delivered, m.is_read, m.is_edited, m.is_deleted, m.reactions, m.expires_at, m.created_at,
        m.is_pinned, m.pinned_by, m.pinned_at,
        m.live_location_active, m.live_location_expires_at,
        m.reply_to_message_id,
        parent_m.sender_id AS reply_sender_id,
        parent_u.name AS reply_sender_name,
        parent_m.message AS reply_message,
        parent_m.attachment_type AS reply_attachment_type,
        parent_m.attachment_name AS reply_attachment_name,
        parent_m.is_deleted AS reply_is_deleted,
        (m.sender_id = $2) AS is_mine
       FROM messages m
       LEFT JOIN messages parent_m ON parent_m.id = m.reply_to_message_id
       LEFT JOIN users parent_u ON parent_u.id = parent_m.sender_id
       WHERE m.conversation_id = $1
       ORDER BY m.created_at ASC`,
      [conversationId, authUserId]
    );

    res.json({
      success: true,
      data: result.rows,
    });
  } catch (error) {
    console.error("Get messages error:", error.message);
    res.status(500).json({
      success: false,
      message: "Failed to fetch messages",
    });
  }
});


// UPLOAD ATTACHMENT AND CREATE MESSAGE
router.post("/upload", uploadSingleFile, async (req, res) => {
  try {
    const { conversationId, message, attachmentType, replyToMessageId, nonce, isEncrypted } = req.body;
    const file = req.file;
    const authUserId = req.user.id;

    if (!conversationId || !file) {
      if (file && file.path && fs.existsSync(file.path)) {
        try { fs.unlinkSync(file.path); } catch (_) {}
      }
      return res.status(400).json({
        success: false,
        message: "conversationId and file are required",
      });
    }

    // Verify conversation membership using req.user.id
    const memberCheck = await pool.query(
      `SELECT 1 FROM conversation_members WHERE conversation_id = $1 AND user_id = $2`,
      [conversationId, authUserId]
    );

    if (memberCheck.rows.length === 0) {
      if (file && file.path && fs.existsSync(file.path)) {
        try { fs.unlinkSync(file.path); } catch (_) {}
      }
      return res.status(403).json({
        success: false,
        message: "Not authorized to upload attachments to this conversation",
      });
    }

    const hostIp = req.headers.host || "localhost:5000";
    const attachmentUrl = `http://${hostIp}/messages/attachments/file/${file.filename}`;
    
    // Fix multer latin1 charset bug for UTF-8 / Emoji / Unicode filenames
    let rawOriginalName = file.originalname;
    try {
      rawOriginalName = Buffer.from(file.originalname, "latin1").toString("utf8");
    } catch (_) {}
    const originalName = path.basename(rawOriginalName).replace(/[\0\r\n]/g, "");
    const fileSize = file.size;

    // NEW: Disappearing Messages — inherit the conversation's active timer, if any
    let expiresAt = null;
    try {
      const convRes = await pool.query(
        "SELECT disappearing_timer_seconds FROM conversations WHERE id = $1",
        [conversationId]
      );
      const timerSeconds = convRes.rows[0]?.disappearing_timer_seconds;
      if (timerSeconds && Number(timerSeconds) > 0) {
        expiresAt = new Date(Date.now() + Number(timerSeconds) * 1000);
      }
    } catch (timerErr) {
      console.error("Error resolving disappearing timer for upload:", timerErr.message);
    }

    const result = await pool.query(
      `INSERT INTO messages (conversation_id, sender_id, message, attachment_url, attachment_type, attachment_name, attachment_size, reply_to_message_id, nonce, is_encrypted, is_delivered, is_read, expires_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, false, false, $11)
       RETURNING id, conversation_id, sender_id, message, attachment_url, attachment_type, attachment_name, attachment_size, reply_to_message_id, nonce, is_encrypted, is_delivered, is_read, is_edited, is_deleted, reactions, expires_at, created_at`,
      [
        conversationId,
        authUserId,
        message || "",
        attachmentUrl,
        attachmentType || "file",
        originalName,
        fileSize,
        replyToMessageId || null,
        nonce || null,
        isEncrypted !== undefined ? (isEncrypted === "true" || isEncrypted === true) : true,
        expiresAt,
      ]
    );

    const newMessage = result.rows[0];
    console.log("Attachment message created securely:", newMessage.id);

    res.status(201).json({
      success: true,
      message: "Attachment uploaded successfully",
      data: newMessage,
    });
  } catch (error) {
    console.error("Upload error:", error.message);
    if (req.file && req.file.path && fs.existsSync(req.file.path)) {
      try { fs.unlinkSync(req.file.path); } catch (_) {}
    }
    res.status(500).json({
      success: false,
      message: error.message || "Failed to upload attachment",
    });
  }
});

// SEND MESSAGE
router.post("/", async (req, res) => {
  try {
    const { conversationId, senderId, message, attachmentUrl, attachmentType, attachmentName, attachmentSize, replyToMessageId, nonce, isEncrypted } = req.body;

    if (!conversationId || !senderId || (!message && !attachmentUrl)) {
      return res.status(400).json({
        success: false,
        message: "conversationId, senderId and message or attachment are required",
      });
    }

    const result = await pool.query(
      `INSERT INTO messages (conversation_id, sender_id, message, attachment_url, attachment_type, attachment_name, attachment_size, reply_to_message_id, nonce, is_encrypted, is_delivered, is_read)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, false, false)
       RETURNING id, conversation_id, sender_id, message, attachment_url, attachment_type, attachment_name, attachment_size, reply_to_message_id, nonce, is_encrypted, is_delivered, is_read, is_edited, is_deleted, reactions, created_at`,
      [conversationId, senderId, message || "", attachmentUrl || null, attachmentType || null, attachmentName || null, attachmentSize || null, replyToMessageId || null, nonce || null, isEncrypted !== undefined ? isEncrypted : true]
    );

    res.status(201).json({
      success: true,
      message: "Message sent successfully",
      data: result.rows[0],
    });
  } catch (error) {
    console.error("Send message error:", error.message);

    res.status(500).json({
      success: false,
      message: "Failed to send message",
    });
  }
});

// EDIT MESSAGE
router.put("/:messageId", async (req, res) => {
  try {
    const { messageId } = req.params;
    const { senderId, message } = req.body;

    if (!senderId || !message) {
      return res.status(400).json({
        success: false,
        message: "senderId and message are required",
      });
    }

    const checkMsg = await pool.query("SELECT * FROM messages WHERE id = $1", [messageId]);
    if (checkMsg.rows.length === 0) {
      return res.status(404).json({ success: false, message: "Message not found" });
    }

    if (String(checkMsg.rows[0].sender_id) !== String(senderId)) {
      return res.status(403).json({ success: false, message: "You can only edit your own messages" });
    }

    if (checkMsg.rows[0].is_deleted) {
      return res.status(400).json({ success: false, message: "Cannot edit a deleted message" });
    }

    const result = await pool.query(
      `UPDATE messages
       SET message = $1, is_edited = true
       WHERE id = $2 AND sender_id = $3 AND is_deleted = false
       RETURNING id, conversation_id, sender_id, message, is_delivered, is_read, is_edited, is_deleted, created_at`,
      [message, messageId, senderId]
    );

    res.json({
      success: true,
      message: "Message edited successfully",
      data: result.rows[0],
    });
  } catch (error) {
    console.error("Edit message error:", error.message);
    res.status(500).json({ success: false, message: "Failed to edit message" });
  }
});

// DELETE MESSAGE (SOFT DELETE)
router.delete("/:messageId", async (req, res) => {
  try {
    const { messageId } = req.params;
    const { senderId } = req.body;

    if (!senderId) {
      return res.status(400).json({
        success: false,
        message: "senderId is required",
      });
    }

    const checkMsg = await pool.query("SELECT * FROM messages WHERE id = $1", [messageId]);
    if (checkMsg.rows.length === 0) {
      return res.status(404).json({ success: false, message: "Message not found" });
    }

    if (String(checkMsg.rows[0].sender_id) !== String(senderId)) {
      return res.status(403).json({ success: false, message: "You can only delete your own messages" });
    }

    const result = await pool.query(
      `UPDATE messages
       SET is_deleted = true
       WHERE id = $1 AND sender_id = $2
       RETURNING id, conversation_id, sender_id, message, is_delivered, is_read, is_edited, is_deleted, created_at`,
      [messageId, senderId]
    );

    res.json({
      success: true,
      message: "Message deleted successfully",
      data: result.rows[0],
    });
  } catch (error) {
    console.error("Delete message error:", error.message);
    res.status(500).json({ success: false, message: "Failed to delete message" });
  }
});

// GET USER STATUS / LAST SEEN
router.get("/user-status/:userId", async (req, res) => {
  try {
    const { userId } = req.params;
    const result = await pool.query(
      "SELECT id, name, is_online, last_seen_at FROM users WHERE id = $1",
      [userId]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: "User not found" });
    }
    res.json({
      success: true,
      data: result.rows[0],
    });
  } catch (error) {
    console.error("Error getting user status:", error.message);
    res.status(500).json({ success: false, message: "Server error" });
  }
});

// GET DISAPPEARING MESSAGES TIMER FOR A CONVERSATION
router.get("/disappearing-timer/:conversationId", async (req, res) => {
  try {
    const { conversationId } = req.params;
    const authUserId = req.user.id;

    const memberCheck = await pool.query(
      "SELECT 1 FROM conversation_members WHERE conversation_id = $1 AND user_id = $2",
      [conversationId, authUserId]
    );
    if (memberCheck.rows.length === 0) {
      return res.status(403).json({ success: false, message: "Not authorized for this conversation" });
    }

    const result = await pool.query(
      "SELECT disappearing_timer_seconds FROM conversations WHERE id = $1",
      [conversationId]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: "Conversation not found" });
    }

    res.json({
      success: true,
      disappearingTimerSeconds: result.rows[0].disappearing_timer_seconds || 0,
    });
  } catch (error) {
    console.error("Get disappearing timer error:", error.message);
    res.status(500).json({ success: false, message: "Server error" });
  }
});

// GET SHARED MEDIA GALLERY FOR A CONVERSATION (images, files, audio)
router.get("/media/:conversationId", async (req, res) => {
  try {
    const { conversationId } = req.params;
    const authUserId = req.user.id;

    const memberCheck = await pool.query(
      "SELECT 1 FROM conversation_members WHERE conversation_id = $1 AND user_id = $2",
      [conversationId, authUserId]
    );
    if (memberCheck.rows.length === 0) {
      return res.status(403).json({ success: false, message: "Not authorized for this conversation" });
    }

    const result = await pool.query(
      `SELECT id, conversation_id, sender_id, attachment_url, attachment_type, attachment_name, attachment_size, created_at
       FROM messages
       WHERE conversation_id = $1
         AND is_deleted = false
         AND attachment_url IS NOT NULL
         AND attachment_type IN ('image', 'file', 'audio')
       ORDER BY created_at DESC`,
      [conversationId]
    );

    res.json({
      success: true,
      data: result.rows,
    });
  } catch (error) {
    console.error("Get media gallery error:", error.message);
    res.status(500).json({ success: false, message: "Failed to fetch media" });
  }
});

// GET "ON THIS DAY" MEMORIES — messages sent on this same month/day in previous years
router.get("/on-this-day/:conversationId", async (req, res) => {
  try {
    const { conversationId } = req.params;
    const authUserId = req.user.id;

    const memberCheck = await pool.query(
      "SELECT 1 FROM conversation_members WHERE conversation_id = $1 AND user_id = $2",
      [conversationId, authUserId]
    );
    if (memberCheck.rows.length === 0) {
      return res.status(403).json({ success: false, message: "Not authorized for this conversation" });
    }

    const result = await pool.query(
      `SELECT id, conversation_id, sender_id, message, attachment_type, attachment_name, created_at,
              EXTRACT(YEAR FROM created_at)::int AS year_sent
       FROM messages
       WHERE conversation_id = $1
         AND is_deleted = false
         AND EXTRACT(MONTH FROM created_at) = EXTRACT(MONTH FROM NOW())
         AND EXTRACT(DAY FROM created_at) = EXTRACT(DAY FROM NOW())
         AND EXTRACT(YEAR FROM created_at) < EXTRACT(YEAR FROM NOW())
       ORDER BY created_at DESC
       LIMIT 30`,
      [conversationId]
    );

    res.json({
      success: true,
      data: result.rows,
    });
  } catch (error) {
    console.error("Get on-this-day memories error:", error.message);
    res.status(500).json({ success: false, message: "Failed to fetch memories" });
  }
});

// GET COUPLE STATUS FOR A USER
router.get("/couple-status/:userId", async (req, res) => {
  try {
    const { userId } = req.params;
    const result = await pool.query(
      "SELECT user_id, status, custom_text, updated_at FROM couple_user_status WHERE user_id = $1",
      [userId]
    );
    res.json({
      success: true,
      data: result.rows[0] || { user_id: Number(userId), status: "online", custom_text: null, updated_at: new Date() },
    });
  } catch (error) {
    console.error("Get couple status error:", error.message);
    res.status(500).json({ success: false, message: "Failed to fetch status" });
  }
});

// ==================================================
// PHASE 4 — REST API ENDPOINTS
// ==================================================

// 1. IMPORTANT DATES
router.get("/important-dates", async (req, res) => {
  try {
    const result = await pool.query(
      "SELECT id, title, date_type, date_value, note, created_by, created_at, updated_at FROM important_dates ORDER BY date_value ASC"
    );
    res.json({ success: true, data: result.rows });
  } catch (error) {
    console.error("Get important dates error:", error.message);
    res.status(500).json({ success: false, message: "Failed to fetch important dates" });
  }
});

router.post("/important-dates", async (req, res) => {
  try {
    const { title, date_type, date_value, note } = req.body;
    const userId = req.user.userId;
    if (!title || !date_value) {
      return res.status(400).json({ success: false, message: "Title and date_value are required" });
    }
    const result = await pool.query(
      `INSERT INTO important_dates (title, date_type, date_value, note, created_by)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING id, title, date_type, date_value, note, created_by, created_at, updated_at`,
      [title, date_type || 'custom', date_value, note || null, userId]
    );
    res.json({ success: true, data: result.rows[0] });
  } catch (error) {
    console.error("Create important date error:", error.message);
    res.status(500).json({ success: false, message: "Failed to create important date" });
  }
});

router.put("/important-dates/:id", async (req, res) => {
  try {
    const { id } = req.params;
    const { title, date_type, date_value, note } = req.body;
    const result = await pool.query(
      `UPDATE important_dates
       SET title = COALESCE($1, title),
           date_type = COALESCE($2, date_type),
           date_value = COALESCE($3, date_value),
           note = COALESCE($4, note),
           updated_at = NOW()
       WHERE id = $5
       RETURNING id, title, date_type, date_value, note, created_by, created_at, updated_at`,
      [title, date_type, date_value, note, id]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: "Date not found" });
    }
    res.json({ success: true, data: result.rows[0] });
  } catch (error) {
    console.error("Update important date error:", error.message);
    res.status(500).json({ success: false, message: "Failed to update important date" });
  }
});

router.delete("/important-dates/:id", async (req, res) => {
  try {
    const { id } = req.params;
    await pool.query("DELETE FROM important_dates WHERE id = $1", [id]);
    res.json({ success: true, message: "Date deleted successfully" });
  } catch (error) {
    console.error("Delete important date error:", error.message);
    res.status(500).json({ success: false, message: "Failed to delete important date" });
  }
});

// 2. DAILY QUESTION
const DEFAULT_QUESTIONS = [
  "What is one thing you love about me?",
  "What should we do together this weekend?",
  "What is your favorite memory of us?",
  "What made you smile today?",
  "Where is your dream vacation with me?",
  "What song reminds you of us?",
  "What is your favorite date we've had?"
];

router.get("/daily-question/today", async (req, res) => {
  try {
    const userId = req.user.userId;
    const todayStr = new Date().toISOString().split('T')[0];

    let qRes = await pool.query("SELECT * FROM daily_questions WHERE question_date = $1", [todayStr]);
    let question;
    if (qRes.rows.length === 0) {
      const qIndex = Math.floor(Math.abs(new Date(todayStr).getTime()) / (1000 * 60 * 60 * 24)) % DEFAULT_QUESTIONS.length;
      const qText = DEFAULT_QUESTIONS[qIndex];
      const insertRes = await pool.query(
        "INSERT INTO daily_questions (question_text, question_date) VALUES ($1, $2) ON CONFLICT (question_date) DO UPDATE SET question_text = EXCLUDED.question_text RETURNING *",
        [qText, todayStr]
      );
      question = insertRes.rows[0];
    } else {
      question = qRes.rows[0];
    }

    const answersRes = await pool.query(
      "SELECT user_id, answer_text, answered_at FROM daily_question_answers WHERE question_id = $1",
      [question.id]
    );

    const answers = answersRes.rows;
    const myAnswerObj = answers.find(a => Number(a.user_id) === Number(userId));
    const partnerAnswerObj = answers.find(a => Number(a.user_id) !== Number(userId));

    const bothAnswered = answers.length >= 2;
    const myAnswer = myAnswerObj ? myAnswerObj.answer_text : null;
    
    // STRICT SECURITY RULE: Partner answer is NEVER revealed until requesting user has ALSO answered!
    const partnerAnswer = (myAnswer && partnerAnswerObj) ? partnerAnswerObj.answer_text : null;
    const hasPartnerAnswered = !!partnerAnswerObj;

    res.json({
      success: true,
      data: {
        id: question.id,
        questionText: question.question_text,
        questionDate: question.question_date,
        myAnswer,
        partnerAnswer,
        hasPartnerAnswered,
        bothAnswered,
      }
    });
  } catch (error) {
    console.error("Get daily question error:", error.message);
    res.status(500).json({ success: false, message: "Failed to fetch daily question" });
  }
});

router.post("/daily-question/answer", async (req, res) => {
  try {
    const userId = req.user.userId;
    const { question_id, answer_text } = req.body;
    if (!question_id || !answer_text) {
      return res.status(400).json({ success: false, message: "question_id and answer_text are required" });
    }

    await pool.query(
      `INSERT INTO daily_question_answers (question_id, user_id, answer_text)
       VALUES ($1, $2, $3)
       ON CONFLICT (question_id, user_id) DO UPDATE SET answer_text = EXCLUDED.answer_text, answered_at = NOW()`,
      [question_id, userId, answer_text]
    );

    const answersRes = await pool.query(
      "SELECT user_id, answer_text FROM daily_question_answers WHERE question_id = $1",
      [question_id]
    );

    const answers = answersRes.rows;
    const bothAnswered = answers.length >= 2;

    res.json({
      success: true,
      data: {
        question_id,
        myAnswer: answer_text,
        bothAnswered,
      }
    });
  } catch (error) {
    console.error("Submit daily question answer error:", error.message);
    res.status(500).json({ success: false, message: "Failed to submit answer" });
  }
});

// 3. PRIVATE MEMORIES
router.get("/memories", async (req, res) => {
  try {
    const result = await pool.query(
      "SELECT id, type, media_url, caption, memory_date, created_by, created_at FROM private_memories ORDER BY memory_date DESC"
    );
    res.json({ success: true, data: result.rows });
  } catch (error) {
    console.error("Get memories error:", error.message);
    res.status(500).json({ success: false, message: "Failed to fetch memories" });
  }
});

router.post("/memories", upload.single("media"), async (req, res) => {
  try {
    const userId = req.user.userId;
    const { caption, memory_date, type } = req.body;
    
    let mediaUrl = req.body.media_url || "";
    if (req.file) {
      mediaUrl = `/messages/media/${req.file.filename}`;
    }

    if (!mediaUrl) {
      return res.status(400).json({ success: false, message: "Media file or media_url is required" });
    }

    const result = await pool.query(
      `INSERT INTO private_memories (type, media_url, caption, memory_date, created_by)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING id, type, media_url, caption, memory_date, created_by, created_at`,
      [type || 'photo', mediaUrl, caption || null, memory_date || new Date(), userId]
    );

    res.json({ success: true, data: result.rows[0] });
  } catch (error) {
    console.error("Create memory error:", error.message);
    res.status(500).json({ success: false, message: "Failed to create memory" });
  }
});

router.delete("/memories/:id", async (req, res) => {
  try {
    const { id } = req.params;
    await pool.query("DELETE FROM private_memories WHERE id = $1", [id]);
    res.json({ success: true, message: "Memory deleted successfully" });
  } catch (error) {
    console.error("Delete memory error:", error.message);
    res.status(500).json({ success: false, message: "Failed to delete memory" });
  }
});

// 4. SHARED NOTES
router.get("/notes", async (req, res) => {
  try {
    const result = await pool.query(
      "SELECT id, title, content, created_by, created_at, updated_at FROM shared_notes ORDER BY updated_at DESC"
    );
    res.json({ success: true, data: result.rows });
  } catch (error) {
    console.error("Get notes error:", error.message);
    res.status(500).json({ success: false, message: "Failed to fetch notes" });
  }
});

router.post("/notes", async (req, res) => {
  try {
    const userId = req.user.userId;
    const { title, content } = req.body;
    if (!title || !content) {
      return res.status(400).json({ success: false, message: "Title and content are required" });
    }

    const result = await pool.query(
      `INSERT INTO shared_notes (title, content, created_by)
       VALUES ($1, $2, $3)
       RETURNING id, title, content, created_by, created_at, updated_at`,
      [title, content, userId]
    );

    res.json({ success: true, data: result.rows[0] });
  } catch (error) {
    console.error("Create note error:", error.message);
    res.status(500).json({ success: false, message: "Failed to create note" });
  }
});

router.put("/notes/:id", async (req, res) => {
  try {
    const { id } = req.params;
    const { title, content } = req.body;

    const result = await pool.query(
      `UPDATE shared_notes
       SET title = COALESCE($1, title),
           content = COALESCE($2, content),
           updated_at = NOW()
       WHERE id = $3
       RETURNING id, title, content, created_by, created_at, updated_at`,
      [title, content, id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: "Note not found" });
    }

    res.json({ success: true, data: result.rows[0] });
  } catch (error) {
    console.error("Update note error:", error.message);
    res.status(500).json({ success: false, message: "Failed to update note" });
  }
});

router.delete("/notes/:id", async (req, res) => {
  try {
    const { id } = req.params;
    await pool.query("DELETE FROM shared_notes WHERE id = $1", [id]);
    res.json({ success: true, message: "Note deleted successfully" });
  } catch (error) {
    console.error("Delete note error:", error.message);
    res.status(500).json({ success: false, message: "Failed to delete note" });
  }
});

// 5. COUPLE ROUTINES
router.get("/routines", async (req, res) => {
  try {
    const userId = req.user.userId;
    const result = await pool.query(
      "SELECT user_id, morning_enabled, morning_time, night_enabled, night_time, custom_morning_msg, custom_night_msg, sound_enabled, updated_at FROM couple_routines WHERE user_id = $1",
      [userId]
    );
    res.json({
      success: true,
      data: result.rows[0] || {
        user_id: userId,
        morning_enabled: false,
        morning_time: "08:00",
        night_enabled: false,
        night_time: "22:00",
        custom_morning_msg: null,
        custom_night_msg: null,
        sound_enabled: true,
      }
    });
  } catch (error) {
    console.error("Get routines error:", error.message);
    res.status(500).json({ success: false, message: "Failed to fetch routines" });
  }
});

router.post("/routines", async (req, res) => {
  try {
    const userId = req.user.userId;
    const { morning_enabled, morning_time, night_enabled, night_time, custom_morning_msg, custom_night_msg, sound_enabled } = req.body;

    const result = await pool.query(
      `INSERT INTO couple_routines (user_id, morning_enabled, morning_time, night_enabled, night_time, custom_morning_msg, custom_night_msg, sound_enabled, updated_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW())
       ON CONFLICT (user_id) DO UPDATE SET
         morning_enabled = EXCLUDED.morning_enabled,
         morning_time = EXCLUDED.morning_time,
         night_enabled = EXCLUDED.night_enabled,
         night_time = EXCLUDED.night_time,
         custom_morning_msg = EXCLUDED.custom_morning_msg,
         custom_night_msg = EXCLUDED.custom_night_msg,
         sound_enabled = EXCLUDED.sound_enabled,
         updated_at = NOW()
       RETURNING user_id, morning_enabled, morning_time, night_enabled, night_time, custom_morning_msg, custom_night_msg, sound_enabled, updated_at`,
      [userId, morning_enabled ?? false, morning_time || "08:00", night_enabled ?? false, night_time || "22:00", custom_morning_msg || null, custom_night_msg || null, sound_enabled ?? true]
    );

    res.json({ success: true, data: result.rows[0] });
  } catch (error) {
    console.error("Save routines error:", error.message);
    res.status(500).json({ success: false, message: "Failed to save routines" });
  }
});

module.exports = router;