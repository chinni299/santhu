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

// Migration for Call History
pool.query(`
  CREATE TABLE IF NOT EXISTS call_logs (
    id SERIAL PRIMARY KEY,
    conversation_id INTEGER NOT NULL,
    caller_id INTEGER NOT NULL,
    recipient_id INTEGER NOT NULL,
    is_video_call BOOLEAN DEFAULT false,
    status VARCHAR(20) NOT NULL DEFAULT 'ringing', -- ringing | answered | missed | declined | cancelled
    duration_seconds INTEGER DEFAULT 0,
    started_at TIMESTAMPTZ DEFAULT NOW(),
    answered_at TIMESTAMPTZ,
    ended_at TIMESTAMPTZ
  );
`).then(() => {
  console.log("call_logs table verified ✅");
}).catch((err) => {
  console.error("Migration error for call_logs table:", err.message);
});

// Migration for Scheduled Messages
pool.query(`
  CREATE TABLE IF NOT EXISTS scheduled_messages (
    id SERIAL PRIMARY KEY,
    conversation_id INTEGER NOT NULL,
    sender_id INTEGER NOT NULL,
    message TEXT NOT NULL,
    send_at TIMESTAMPTZ NOT NULL,
    is_sent BOOLEAN DEFAULT false,
    is_cancelled BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW()
  );
`).then(() => {
  console.log("scheduled_messages table verified ✅");
}).catch((err) => {
  console.error("Migration error for scheduled_messages table:", err.message);
});

// Migration for Shared Diary
pool.query(`
  CREATE TABLE IF NOT EXISTS diary_entries (
    id SERIAL PRIMARY KEY,
    conversation_id INTEGER NOT NULL,
    author_id INTEGER NOT NULL,
    entry_text TEXT NOT NULL,
    mood VARCHAR(10),
    photo_url TEXT,
    entry_date DATE NOT NULL DEFAULT CURRENT_DATE,
    is_deleted BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW()
  );
`).then(() => {
  console.log("diary_entries table verified ✅");
}).catch((err) => {
  console.error("Migration error for diary_entries table:", err.message);
});

// Migration for Shared Countdown / Anniversary Tracker
pool.query(`
  CREATE TABLE IF NOT EXISTS special_dates (
    id SERIAL PRIMARY KEY,
    conversation_id INTEGER NOT NULL,
    title VARCHAR(120) NOT NULL,
    event_date DATE NOT NULL,
    is_recurring_yearly BOOLEAN DEFAULT true,
    created_by INTEGER NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
  );
`).then(() => {
  console.log("special_dates table verified ✅");
}).catch((err) => {
  console.error("Migration error for special_dates table:", err.message);
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

// GET SECURE PRIVATE ATTACHMENT BY FILENAME (Optimized Fast Serving)
router.get("/attachments/file/:filename", async (req, res) => {
  try {
    const { filename } = req.params;
    const safeFilename = path.basename(filename).replace(/[^a-zA-Z0-9.\-_]/g, "");
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
    const isInline = [".jpg", ".jpeg", ".png", ".webp", ".gif", ".m4a", ".mp3", ".wav", ".aac"].includes(ext);

    res.setHeader("Content-Type", contentType);
    res.setHeader("Content-Disposition", isInline ? "inline" : `attachment; filename="${safeFilename}"`);
    res.setHeader("Cache-Control", "public, max-age=86400, immutable");

    return res.sendFile(filePath);
  } catch (err) {
    console.error("Error serving attachment:", err.message);
    return res.status(500).json({ success: false, message: "Error serving file" });
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

// GET CALL HISTORY FOR A CONVERSATION
router.get("/calls/:conversationId", async (req, res) => {
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
      `SELECT id, conversation_id, caller_id, recipient_id, is_video_call, status, duration_seconds, started_at, answered_at, ended_at
       FROM call_logs
       WHERE conversation_id = $1
       ORDER BY started_at DESC
       LIMIT 100`,
      [conversationId]
    );

    res.json({ success: true, data: result.rows });
  } catch (error) {
    console.error("Get call history error:", error.message);
    res.status(500).json({ success: false, message: "Failed to fetch call history" });
  }
});

// GET PENDING SCHEDULED MESSAGES FOR A CONVERSATION (sender's own, not-yet-sent)
router.get("/scheduled/:conversationId", async (req, res) => {
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
      `SELECT id, conversation_id, sender_id, message, send_at, is_sent, is_cancelled, created_at
       FROM scheduled_messages
       WHERE conversation_id = $1 AND sender_id = $2 AND is_sent = false AND is_cancelled = false
       ORDER BY send_at ASC`,
      [conversationId, authUserId]
    );

    res.json({ success: true, data: result.rows });
  } catch (error) {
    console.error("Get scheduled messages error:", error.message);
    res.status(500).json({ success: false, message: "Failed to fetch scheduled messages" });
  }
});

// GET SPECIAL DATES (ANNIVERSARIES / COUNTDOWNS) FOR A CONVERSATION
router.get("/special-dates/:conversationId", async (req, res) => {
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
      `SELECT id, conversation_id, title, event_date, is_recurring_yearly, created_by, created_at
       FROM special_dates
       WHERE conversation_id = $1
       ORDER BY event_date ASC`,
      [conversationId]
    );

    res.json({ success: true, data: result.rows });
  } catch (error) {
    console.error("Get special dates error:", error.message);
    res.status(500).json({ success: false, message: "Failed to fetch special dates" });
  }
});

// GET SHARED DIARY ENTRIES FOR A CONVERSATION
router.get("/diary/:conversationId", async (req, res) => {
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
      `SELECT d.id, d.conversation_id, d.author_id, u.name AS author_name,
              d.entry_text, d.mood, d.photo_url, d.entry_date, d.created_at
       FROM diary_entries d
       LEFT JOIN users u ON u.id = d.author_id
       WHERE d.conversation_id = $1 AND d.is_deleted = false
       ORDER BY d.entry_date DESC, d.created_at DESC`,
      [conversationId]
    );

    res.json({ success: true, data: result.rows });
  } catch (error) {
    console.error("Get diary entries error:", error.message);
    res.status(500).json({ success: false, message: "Failed to fetch diary entries" });
  }
});

// UPLOAD A PHOTO FOR A DIARY ENTRY (returns the URL; entry itself is created via socket)
router.post("/diary/upload-photo", uploadSingleFile, async (req, res) => {
  try {
    const { conversationId } = req.body;
    const file = req.file;
    const authUserId = req.user.id;

    if (!conversationId || !file) {
      if (file && file.path && fs.existsSync(file.path)) {
        try { fs.unlinkSync(file.path); } catch (_) {}
      }
      return res.status(400).json({ success: false, message: "conversationId and file are required" });
    }

    const memberCheck = await pool.query(
      "SELECT 1 FROM conversation_members WHERE conversation_id = $1 AND user_id = $2",
      [conversationId, authUserId]
    );
    if (memberCheck.rows.length === 0) {
      if (file.path && fs.existsSync(file.path)) {
        try { fs.unlinkSync(file.path); } catch (_) {}
      }
      return res.status(403).json({ success: false, message: "Not authorized for this conversation" });
    }

    const hostIp = req.headers.host || "localhost:5000";
    const photoUrl = `http://${hostIp}/messages/diary/attachments/${file.filename}`;

    res.status(201).json({ success: true, url: photoUrl });
  } catch (error) {
    console.error("Diary photo upload error:", error.message);
    if (req.file && req.file.path && fs.existsSync(req.file.path)) {
      try { fs.unlinkSync(req.file.path); } catch (_) {}
    }
    res.status(500).json({ success: false, message: "Failed to upload photo" });
  }
});

// GET A DIARY PHOTO (authorized by conversation membership, not tied to the messages table)
router.get("/diary/attachments/:filename", async (req, res) => {
  try {
    const { filename } = req.params;
    const authUserId = req.user.id;
    const safeFilename = path.basename(filename).replace(/[^a-zA-Z0-9.\-_]/g, "");

    const entryRes = await pool.query(
      "SELECT conversation_id FROM diary_entries WHERE photo_url LIKE $1 LIMIT 1",
      [`%${safeFilename}`]
    );
    if (entryRes.rows.length === 0) {
      return res.status(404).json({ success: false, message: "Photo unavailable" });
    }

    const memberCheck = await pool.query(
      "SELECT 1 FROM conversation_members WHERE conversation_id = $1 AND user_id = $2",
      [entryRes.rows[0].conversation_id, authUserId]
    );
    if (memberCheck.rows.length === 0) {
      return res.status(403).json({ success: false, message: "Not authorized" });
    }

    const filePath = path.join(uploadsDir, safeFilename);
    if (!fs.existsSync(filePath)) {
      return res.status(404).json({ success: false, message: "Photo unavailable" });
    }

    const ext = path.extname(safeFilename).toLowerCase();
    const mimeTypes = { ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png", ".webp": "image/webp", ".gif": "image/gif" };
    res.setHeader("Content-Type", mimeTypes[ext] || "application/octet-stream");
    res.setHeader("Content-Disposition", "inline");
    res.setHeader("Cache-Control", "private, no-cache, no-store, must-revalidate");
    fs.createReadStream(filePath).pipe(res);
  } catch (error) {
    console.error("Diary photo fetch error:", error.message);
    res.status(500).json({ success: false, message: "Internal server error" });
  }
});

module.exports = router;