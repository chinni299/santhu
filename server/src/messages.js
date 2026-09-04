const express = require("express");
const pool = require("./db");
const multer = require("multer");
const path = require("path");
const fs = require("fs");

console.log("MESSAGES ROUTE LOADED ✅");

const router = express.Router();

const uploadsDir = path.join(__dirname, "../uploads");
if (!fs.existsSync(uploadsDir)) {
  fs.mkdirSync(uploadsDir, { recursive: true });
}

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, uploadsDir);
  },
  filename: (req, file, cb) => {
    const uniqueSuffix = Date.now() + "-" + Math.round(Math.random() * 1e9);
    const ext = path.extname(file.originalname).toLowerCase();
    cb(null, uniqueSuffix + ext);
  },
});

const fileFilter = (req, file, cb) => {
  cb(null, true);
};

const upload = multer({
  storage,
  limits: { fileSize: 25 * 1024 * 1024 },
  fileFilter,
});

// GET TEST ROUTE (Verify router mounting)
router.get("/test", (req, res) => {
  res.json({
    success: true,
    message: "Messages router is mounted correctly ✅",
  });
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

    const result = await pool.query(
      `SELECT 
        c.id AS conversation_id,
        other_u.id AS other_user_id,
        other_u.name AS other_user_name,
        other_u.email AS other_user_email,
        CASE 
          WHEN latest_m.is_deleted = true THEN 'This message was deleted' 
          WHEN latest_m.attachment_type = 'image' THEN '📷 Photo'
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

    const result = await pool.query(
      `SELECT 
        m.id, m.conversation_id, m.sender_id, m.message, 
        m.attachment_url, m.attachment_type, m.attachment_name, m.attachment_size,
        m.is_delivered, m.is_read, m.is_edited, m.is_deleted, m.reactions, m.created_at,
        m.reply_to_message_id,
        parent_m.sender_id AS reply_sender_id,
        parent_u.name AS reply_sender_name,
        parent_m.message AS reply_message,
        parent_m.attachment_type AS reply_attachment_type,
        parent_m.attachment_name AS reply_attachment_name,
        parent_m.is_deleted AS reply_is_deleted
       FROM messages m
       LEFT JOIN messages parent_m ON parent_m.id = m.reply_to_message_id
       LEFT JOIN users parent_u ON parent_u.id = parent_m.sender_id
       WHERE m.conversation_id = $1
       ORDER BY m.created_at ASC`,
      [conversationId]
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
router.post("/upload", upload.single("file"), async (req, res) => {
  try {
    const { conversationId, senderId, message, attachmentType, replyToMessageId } = req.body;
    const file = req.file;

    if (!conversationId || !senderId || !file) {
      return res.status(400).json({
        success: false,
        message: "conversationId, senderId, and file are required",
      });
    }

    const hostIp = "192.168.0.120:5000";
    const attachmentUrl = `http://${hostIp}/uploads/${file.filename}`;
    const originalName = file.originalname;
    const fileSize = file.size;

    const result = await pool.query(
      `INSERT INTO messages (conversation_id, sender_id, message, attachment_url, attachment_type, attachment_name, attachment_size, reply_to_message_id, is_delivered, is_read)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, false, false)
       RETURNING id, conversation_id, sender_id, message, attachment_url, attachment_type, attachment_name, attachment_size, reply_to_message_id, is_delivered, is_read, is_edited, is_deleted, reactions, created_at`,
      [
        conversationId,
        senderId,
        message || "",
        attachmentUrl,
        attachmentType || "file",
        originalName,
        fileSize,
        replyToMessageId || null,
      ]
    );

    const newMessage = result.rows[0];
    console.log("Attachment message created:", newMessage);

    res.status(201).json({
      success: true,
      message: "Attachment uploaded successfully",
      data: newMessage,
    });
  } catch (error) {
    console.error("Upload error:", error.message);
    res.status(500).json({
      success: false,
      message: error.message || "Failed to upload attachment",
    });
  }
});

// SEND MESSAGE
router.post("/", async (req, res) => {
  try {
    const { conversationId, senderId, message, attachmentUrl, attachmentType, attachmentName, attachmentSize, replyToMessageId } = req.body;

    if (!conversationId || !senderId || (!message && !attachmentUrl)) {
      return res.status(400).json({
        success: false,
        message: "conversationId, senderId and message or attachment are required",
      });
    }

    const result = await pool.query(
      `INSERT INTO messages (conversation_id, sender_id, message, attachment_url, attachment_type, attachment_name, attachment_size, reply_to_message_id, is_delivered, is_read)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, false, false)
       RETURNING id, conversation_id, sender_id, message, attachment_url, attachment_type, attachment_name, attachment_size, reply_to_message_id, is_delivered, is_read, is_edited, is_deleted, created_at`,
      [conversationId, senderId, message || "", attachmentUrl || null, attachmentType || null, attachmentName || null, attachmentSize || null, replyToMessageId || null]
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
    const result = await pool.query("SELECT id, name, last_seen_at FROM users WHERE id = $1", [userId]);
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

module.exports = router;