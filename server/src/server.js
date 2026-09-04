const express = require("express");
const http = require("http");
const { Server } = require("socket.io");
const authRoutes = require("./auth");
const messageRoutes = require("./messages");
const cors = require("cors");
require("dotenv").config();

const pool = require("./db");
const admin = require("firebase-admin");
const path = require("path");
const fs = require("fs");

// Initialize Firebase Admin SDK
const serviceAccountPath = path.join(__dirname, "config", "firebase-service-account.json");

if (fs.existsSync(serviceAccountPath)) {
  const serviceAccount = require(serviceAccountPath);
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
  console.log("Firebase Admin SDK initialized successfully ✅");
} else {
  console.warn(
    "⚠️ Firebase service account file not found at server/src/config/firebase-service-account.json. Push notifications logging enabled."
  );
}

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"],
  },
});

app.use(cors());
app.use(express.json());
app.use("/uploads", express.static(path.join(__dirname, "../uploads")));
app.use("/auth", authRoutes);
app.use("/messages", messageRoutes);

console.log("MESSAGES API REGISTERED ✅");

app.get("/", (req, res) => {
  res.json({
    success: true,
    message: "DuoChat backend is running 🚀",
  });
});

// PostgreSQL connection test
app.get("/db-test", async (req, res) => {
  try {
    const result = await pool.query("SELECT NOW()");

    res.json({
      success: true,
      message: "PostgreSQL connected successfully ✅",
      time: result.rows[0].now,
    });
  } catch (error) {
    console.error("Database error:", error.message);

    res.status(500).json({
      success: false,
      message: "PostgreSQL connection failed ❌",
    });
  }
});

// Socket.IO Connection Handler
io.on("connection", (socket) => {
  console.log(`User connected: ${socket.id}`);

  // Join User Room (For global notifications, unread counts & status updates)
  socket.on("joinUserRoom", (data) => {
    const userId = typeof data === "object" && data !== null ? data.userId : data;
    if (userId) {
      const userRoom = `user_${userId}`;
      socket.join(userRoom);
      socket.data.userId = userId;
      console.log(`Socket ${socket.id} joined global user room: ${userRoom}`);
    }
  });

  // Join Conversation Room (For active chat screen)
  socket.on("joinConversation", (data) => {
    const conversationId =
      typeof data === "object" && data !== null ? data.conversationId : data;
    const userId =
      typeof data === "object" && data !== null ? data.userId : null;
    const userName =
      typeof data === "object" && data !== null ? data.userName : null;

    const room = String(conversationId);
    socket.join(room);

    if (userId) {
      const userRoom = `user_${userId}`;
      socket.join(userRoom);
      socket.data.userId = userId;
    }

    socket.data.conversationId = conversationId;
    socket.data.userName = userName;

    console.log(`User ${userId || socket.id} joined conversation room: ${room}`);

    // Notify other users in the room that this user is online
    if (userId) {
      socket.to(room).emit("userOnline", { conversationId, userId, userName });
      io.emit("userOnline", { conversationId, userId, userName });

      // Tell this user about other users currently in the room
      const roomSockets = io.sockets.adapter.rooms.get(room);
      if (roomSockets) {
        for (const socketId of roomSockets) {
          if (socketId !== socket.id) {
            const otherSocket = io.sockets.sockets.get(socketId);
            if (otherSocket && otherSocket.data && otherSocket.data.userId) {
              socket.emit("userOnline", {
                conversationId,
                userId: otherSocket.data.userId,
                userName: otherSocket.data.userName,
              });
            }
          }
        }
      }
    }
  });

  // Send Message Event
  socket.on("sendMessage", async (data) => {
    try {
      const { conversationId, senderId, message, attachmentUrl, attachmentType, attachmentName, attachmentSize, replyToMessageId, messageId, isAlreadySaved, tempMsgId } = data;
      console.log("Message received:", data);

      if (!conversationId || !senderId || (!message && !attachmentUrl)) {
        console.error("Invalid message payload:", data);
        return;
      }

      let newMessage;

      if (messageId || isAlreadySaved) {
        // Message was already saved to DB by /messages/upload endpoint!
        const existingRes = await pool.query(
          `SELECT id, conversation_id, sender_id, message, attachment_url, attachment_type, attachment_name, attachment_size, reply_to_message_id, is_delivered, is_read, is_edited, is_deleted, reactions, created_at
           FROM messages WHERE id = $1`,
          [messageId]
        );
        if (existingRes.rows.length > 0) {
          newMessage = existingRes.rows[0];
        }
      }

      if (!newMessage) {
        // Save to PostgreSQL database
        const result = await pool.query(
          `INSERT INTO messages (conversation_id, sender_id, message, attachment_url, attachment_type, attachment_name, attachment_size, reply_to_message_id, is_delivered, is_read)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, false, false)
           RETURNING id, conversation_id, sender_id, message, attachment_url, attachment_type, attachment_name, attachment_size, reply_to_message_id, is_delivered, is_read, is_edited, is_deleted, reactions, created_at`,
          [conversationId, senderId, message || "", attachmentUrl || null, attachmentType || null, attachmentName || null, attachmentSize || null, replyToMessageId || null]
        );

        newMessage = result.rows[0];
      }

      if (tempMsgId) {
        newMessage.tempMsgId = tempMsgId;
      }

      if (newMessage.reply_to_message_id) {
        const replyRes = await pool.query(
          `SELECT m.sender_id AS reply_sender_id, u.name AS reply_sender_name, m.message AS reply_message,
                  m.attachment_type AS reply_attachment_type, m.attachment_name AS reply_attachment_name, m.is_deleted AS reply_is_deleted
           FROM messages m
           LEFT JOIN users u ON m.sender_id = u.id
           WHERE m.id = $1`,
          [newMessage.reply_to_message_id]
        );
        if (replyRes.rows.length > 0) {
          const parent = replyRes.rows[0];
          newMessage.reply_sender_id = parent.reply_sender_id;
          newMessage.reply_sender_name = parent.reply_sender_name || (Number(parent.reply_sender_id) === 1 ? "User 1" : "User 2");
          newMessage.reply_message = parent.reply_message;
          newMessage.reply_attachment_type = parent.reply_attachment_type;
          newMessage.reply_attachment_name = parent.reply_attachment_name;
          newMessage.reply_is_deleted = parent.reply_is_deleted;
        }
      }

      console.log("Message saved:", newMessage);

      const room = String(conversationId);
      const recipientId = Number(senderId) === 1 ? 2 : 1;

      // Broadcast newMessage to chat room AND recipient user room
      io.to(room).to(`user_${recipientId}`).emit("newMessage", newMessage);
      console.log(`newMessage emitted to room ${room} and user_${recipientId}:`, newMessage);

      // Fetch updated unread count
      const unreadRes = await pool.query(
        `SELECT COUNT(*)::int AS unread_count
         FROM messages
         WHERE conversation_id = $1 AND sender_id = $2 AND is_read = false`,
        [conversationId, senderId]
      );
      const unreadCount = parseInt(unreadRes.rows[0].unread_count || 0, 10);

      io.to(room).to(`user_${recipientId}`).emit("unreadCountUpdate", {
        conversationId,
        senderId,
        unreadCount,
      });
      console.log(`unreadCountUpdate emitted to room ${room}:`, {
        conversationId,
        senderId,
        unreadCount,
      });

      // =========================
      // FCM PUSH NOTIFICATION LOGIC
      // =========================
      const roomSockets = io.sockets.adapter.rooms.get(room);
      let isRecipientActiveInRoom = false;

      if (roomSockets) {
        for (const socketId of roomSockets) {
          const s = io.sockets.sockets.get(socketId);
          if (s && s.data && s.data.conversationId && String(s.data.conversationId) === String(conversationId) && s.data.userId && String(s.data.userId) !== String(senderId)) {
            isRecipientActiveInRoom = true;
            break;
          }
        }
      }

      console.log(`Recipient active in room ${room}: ${isRecipientActiveInRoom}`);

      if (!isRecipientActiveInRoom) {
        const recipientId = Number(senderId) === 1 ? 2 : 1;

        const senderResult = await pool.query("SELECT name FROM users WHERE id = $1", [senderId]);
        const recipientResult = await pool.query("SELECT fcm_token FROM users WHERE id = $1", [recipientId]);

        const senderName = senderResult.rows[0]?.name || (Number(senderId) === 1 ? "User 1" : "User 2");
        const recipientToken = recipientResult.rows[0]?.fcm_token;

        console.log(
          `Push Notification Check: Sender="${senderName}", Recipient=${recipientId}, Token=${
            recipientToken ? recipientToken.substring(0, 15) + '...' : 'NULL'
          }`
        );

        let notifBody = message;
        if (!notifBody || notifBody.trim().length === 0) {
          if (attachmentType === 'image') {
            notifBody = "📷 Photo";
          } else if (attachmentType) {
            notifBody = "📎 File";
          }
        }

        if (recipientToken) {
          if (admin.apps && admin.apps.length > 0) {
            try {
              const response = await admin.messaging().send({
                token: recipientToken,
                notification: {
                  title: senderName,
                  body: notifBody,
                },
                data: {
                  conversationId: String(conversationId),
                  senderId: String(senderId),
                },
              });
              console.log(`FCM Push Notification sent successfully to User ${recipientId}: ${response} 🔔`);
            } catch (fcmErr) {
              console.error(`Error sending FCM Notification: ${fcmErr.message} ❌`);
            }
          } else {
            console.log(
              `[Push Notification Simulation] Title: "${senderName}", Body: "${notifBody}" -> Sent to User ${recipientId} 🔔`
            );
          }
        } else {
          console.log(`No FCM token found for User ${recipientId}. Notification skipped.`);
        }
      }
    } catch (error) {
      console.error("Error saving/broadcasting message:", error.message);
    }
  });

  // Mark Messages Delivered Event
  socket.on("markMessagesDelivered", async (data) => {
    try {
      const { conversationId, userId } = data || {};
      if (!conversationId || !userId) return;

      const result = await pool.query(
        `UPDATE messages
         SET is_delivered = true
         WHERE conversation_id = $1 AND sender_id != $2 AND is_delivered = false
         RETURNING id`,
        [conversationId, userId]
      );

      console.log(
        `Marked ${result.rowCount} messages as delivered for conversation ${conversationId} to recipient ${userId}`
      );

      const room = String(conversationId);
      if (result.rowCount > 0) {
        io.to(room).emit("messagesDelivered", {
          conversationId,
          recipientId: userId,
          deliveredMessageIds: result.rows.map((row) => row.id),
        });
        console.log(`messagesDelivered emitted to room ${room}:`, {
          conversationId,
          recipientId: userId,
        });
      }
    } catch (error) {
      console.error("Error marking messages delivered:", error.message);
    }
  });

  // Mark Messages Seen Event
  socket.on("markMessagesSeen", async (data) => {
    try {
      const { conversationId, userId } = data || {};
      if (!conversationId || !userId) return;

      const result = await pool.query(
        `UPDATE messages
         SET is_read = true, is_delivered = true
         WHERE conversation_id = $1 AND sender_id != $2 AND (is_read = false OR is_delivered = false)
         RETURNING id`,
        [conversationId, userId]
      );

      console.log(
        `Marked ${result.rowCount} messages as read for conversation ${conversationId} by user ${userId}`
      );

      const room = String(conversationId);
      if (result.rowCount > 0) {
        io.to(room).emit("messagesSeen", {
          conversationId,
          readerId: userId,
          seenMessageIds: result.rows.map((row) => row.id),
        });
        console.log(`messagesSeen emitted to room ${room}:`, {
          conversationId,
          readerId: userId,
        });
      }

      // Always broadcast reset unread count for readerId when marking seen
      io.to(room).emit("unreadCountUpdate", {
        conversationId,
        userId,
        unreadCount: 0,
      });
      console.log(`unreadCountUpdate (reset 0) emitted to room ${room}:`, {
        conversationId,
        userId,
        unreadCount: 0,
      });
    } catch (error) {
      console.error("Error marking messages seen:", error.message);
    }
  });

  // Edit Message Event
  socket.on("editMessage", async (data) => {
    try {
      const { conversationId, messageId, senderId, newMessage } = data || {};
      if (!conversationId || !messageId || !senderId || !newMessage) return;

      const checkMsg = await pool.query("SELECT * FROM messages WHERE id = $1", [messageId]);
      if (checkMsg.rows.length === 0 || String(checkMsg.rows[0].sender_id) !== String(senderId)) {
        console.warn(`Unauthorized edit attempt by user ${senderId} on message ${messageId}`);
        return;
      }

      if (checkMsg.rows[0].is_deleted) return;

      const result = await pool.query(
        `UPDATE messages
         SET message = $1, is_edited = true
         WHERE id = $2 AND sender_id = $3 AND is_deleted = false
         RETURNING id, conversation_id, sender_id, message, is_delivered, is_read, is_edited, is_deleted, created_at`,
        [newMessage, messageId, senderId]
      );

      if (result.rowCount > 0) {
        const editedMsg = result.rows[0];
        const room = String(conversationId);
        io.to(room).emit("messageEdited", editedMsg);
        console.log(`messageEdited emitted to room ${room}:`, editedMsg);
      }
    } catch (error) {
      console.error("Error handling editMessage socket event:", error.message);
    }
  });

  // Delete Message Event
  socket.on("deleteMessage", async (data) => {
    try {
      const { conversationId, messageId, senderId } = data || {};
      if (!conversationId || !messageId || !senderId) return;

      const checkMsg = await pool.query("SELECT * FROM messages WHERE id = $1", [messageId]);
      if (checkMsg.rows.length === 0 || String(checkMsg.rows[0].sender_id) !== String(senderId)) {
        console.warn(`Unauthorized delete attempt by user ${senderId} on message ${messageId}`);
        return;
      }

      const result = await pool.query(
        `UPDATE messages
         SET is_deleted = true
         WHERE id = $1 AND sender_id = $2
         RETURNING id, conversation_id, sender_id, message, is_delivered, is_read, is_edited, is_deleted, created_at`,
        [messageId, senderId]
      );

      if (result.rowCount > 0) {
        const room = String(conversationId);
        io.to(room).emit("messageDeleted", {
          conversationId,
          messageId: Number(messageId),
          senderId,
          isDeleted: true,
        });
        console.log(`messageDeleted emitted to room ${room}:`, {
          conversationId,
          messageId,
          senderId,
        });
      }
    } catch (error) {
      console.error("Error handling deleteMessage socket event:", error.message);
    }
  });

  // React to Message Event
  socket.on("reactToMessage", async (data) => {
    try {
      const { conversationId, messageId, userId, emoji } = data || {};
      if (!conversationId || !messageId || !userId) return;

      const checkMsg = await pool.query("SELECT reactions FROM messages WHERE id = $1", [messageId]);
      if (checkMsg.rows.length === 0) return;

      let reactions = checkMsg.rows[0].reactions || {};
      if (!emoji || reactions[userId] === emoji) {
        delete reactions[userId];
      } else {
        reactions[userId] = emoji;
      }

      await pool.query(
        "UPDATE messages SET reactions = $1 WHERE id = $2",
        [reactions, messageId]
      );

      const room = String(conversationId);
      io.to(room).emit("messageReaction", {
        conversationId,
        messageId: Number(messageId),
        reactions,
      });
      console.log(`messageReaction emitted to room ${room}:`, { messageId, reactions });
    } catch (error) {
      console.error("Error handling reactToMessage:", error.message);
    }
  });

  // Typing Event
  socket.on("typing", (data) => {
    const { conversationId, senderId, userName } = data || {};
    const room = String(conversationId);
    console.log(`User typing in room ${room}: ${userName || senderId || 'User'}`);
    socket.to(room).emit("typing", data);
  });

  // Stop Typing Event
  socket.on("stopTyping", (data) => {
    const { conversationId, senderId, userName } = data || {};
    const room = String(conversationId);
    console.log(`User stopped typing in room ${room}: ${userName || senderId || 'User'}`);
    socket.to(room).emit("stopTyping", data);
  });

  socket.on("disconnect", async () => {
    console.log(`User disconnected: ${socket.id}`);
    if (socket.data && socket.data.conversationId && socket.data.userId) {
      const room = String(socket.data.conversationId);
      const userId = socket.data.userId;
      const lastSeenAt = new Date().toISOString();

      try {
        await pool.query("UPDATE users SET last_seen_at = NOW() WHERE id = $1", [userId]);
      } catch (err) {
        console.error("Error updating last_seen_at:", err.message);
      }

      io.to(room).emit("userOffline", {
        conversationId: socket.data.conversationId,
        userId: userId,
        lastSeenAt: lastSeenAt,
      });
      console.log(`User ${userId} went offline in room ${room} at ${lastSeenAt}`);
    }
  });
});

const PORT = process.env.PORT || 5000;

server.listen(PORT, () => {
  console.log(`DuoChat server running on port ${PORT}`);
});