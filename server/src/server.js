const express = require("express");
const http = require("http");
const { Server } = require("socket.io");
const jwt = require("jsonwebtoken");
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

const helmet = require("helmet");
const rateLimit = require("express-rate-limit");

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"],
  },
});

// Production Security Headers via Helmet
app.use(helmet({ crossOriginResourcePolicy: { policy: "cross-origin" } }));
app.use(cors({ origin: "*" })); // JWT Bearer token doesn't require credentials: true
app.use(express.json());

// Rate Limiters
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100, // Limit each IP
  message: { success: false, message: "Too many login/registration attempts. Please try again later." },
});

const apiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 1000,
  message: { success: false, message: "Too many API requests. Please try again later." },
});

app.use("/auth/login", authLimiter);
app.use("/messages", apiLimiter);

// Registration is permanently disabled.
app.all("/auth/register", (req, res) => {
  res.status(404).json({ success: false, message: "Not found" });
});

// Public /uploads static route removed for security (PHASE 3)
app.use("/auth", authRoutes);
app.use("/messages", messageRoutes);

console.log("MESSAGES API REGISTERED ✅");

app.get("/", (req, res) => {
  res.json({
    success: true,
    message: "DuoChat backend is running 🚀",
  });
});

// Helper function for sending privacy-preserving FCM push notifications & cleaning invalid tokens
async function sendPushNotification({ recipientId, title, body, dataPayload }) {
  try {
    const recipientResult = await pool.query("SELECT fcm_token FROM users WHERE id = $1", [recipientId]);
    const recipientToken = recipientResult.rows[0]?.fcm_token;

    if (!recipientToken) {
      console.log(`No FCM token registered for User ${recipientId}. Notification skipped.`);
      return;
    }

    console.log(`Sending Push Notification to User ${recipientId}: Title="${title}", Body="${body}"`);

    if (admin.apps && admin.apps.length > 0) {
      try {
        const response = await admin.messaging().send({
          token: recipientToken,
          notification: {
            title: title,
            body: body,
          },
          data: dataPayload || {},
        });
        console.log(`FCM Push Notification sent successfully to User ${recipientId}: ${response} 🔔`);
      } catch (fcmErr) {
        console.error(`FCM send error for User ${recipientId}: ${fcmErr.message} ❌`);
        const errStr = String(fcmErr.message || fcmErr.code || "");
        if (
          errStr.includes("not-registered") ||
          errStr.includes("invalid-registration-token") ||
          errStr.includes("Requested entity was not found") ||
          errStr.includes("registration-token-not-registered")
        ) {
          await pool.query("UPDATE users SET fcm_token = NULL WHERE id = $1", [recipientId]);
          console.log(`Cleaned up invalid FCM token for User ${recipientId} 🧹`);
        }
      }
    } else {
      console.log(`[Push Notification Simulation] Title: "${title}", Body: "${body}" -> Sent to User ${recipientId} 🔔`);
    }
  } catch (err) {
    console.error(`Error in sendPushNotification for User ${recipientId}:`, err.message);
  }
}

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

// Strict Socket.IO Authentication Middleware (REJECTS unauthenticated connections)
io.use((socket, next) => {
  console.log(`[SERVER SOCKET] Incoming connection. Handshake data:`, JSON.stringify({
    auth: socket.handshake.auth,
    headers: socket.handshake.headers,
    query: socket.handshake.query
  }));

  const token =
    socket.handshake.auth?.token ||
    socket.handshake.headers?.authorization?.split(" ")[1] ||
    socket.handshake.query?.token;

  if (!token) {
    const err = new Error("Authentication error: JWT token required");
    err.data = { code: 401 };
    return next(err);
  }

  try {
    if (!process.env.JWT_SECRET) {
      console.error("[SERVER SOCKET] JWT_SECRET is missing!");
    }
    const decoded = jwt.verify(token, process.env.JWT_SECRET || "duochat_super_secret_key_2026");
    
    // Strict 2-User Enforcement
    const uid = Number(decoded.userId || decoded.id);
    if (uid !== 1 && uid !== 2) {
      console.warn(`[SERVER SOCKET] REJECTED unauthorized userId: ${uid}`);
      const authErr = new Error("Authentication error: Unauthorized identity");
      authErr.data = { code: 403 };
      return next(authErr);
    }
    
    socket.user = decoded;
    console.log(`[SERVER SOCKET] AUTH SUCCESS: User ${uid}`);
    return next();
  } catch (err) {
    const authErr = new Error("Authentication error: Invalid or expired token");
    authErr.data = { code: 401 };
    return next(authErr);
  }
});

// Global active WebRTC calls registry
const activeCalls = new Map(); // conversationId -> { callerId, recipientId, isVideoCall, status }
// Global active user socket connections registry: userId -> Set<socketId>
const userSockets = new Map();

// Socket.IO Connection Handler
io.on("connection", (socket) => {
  const authUserId = socket.user?.userId || socket.user?.id;
  console.log(`[SERVER SOCKET] CLIENT CONNECTED: socketId=${socket.id}`);
  console.log(`[SERVER SOCKET] USER: ${authUserId}`);
  if (authUserId) {
    const numId = Number(authUserId);
    socket.join(`user_${numId}`);
    socket.data.userId = numId;

    if (!userSockets.has(numId)) {
      userSockets.set(numId, new Set());
    }
    const socketSet = userSockets.get(numId);
    socketSet.add(socket.id);

    if (socketSet.size === 1) {
      pool.query("UPDATE users SET is_online = true WHERE id = $1", [numId]).catch(() => {});
      const recipientId = numId === 1 ? 2 : 1;
      io.to(`user_${recipientId}`).emit("userOnline", { userId: numId, conversationId: 1 });
      console.log(`User ${numId} is now ONLINE (1st socket: ${socket.id}) 🟢`);
    } else {
      console.log(`User ${numId} connected additional socket (${socket.id}, active sockets: ${socketSet.size})`);
    }
  }

  // Join User Room
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
    console.log(`[SERVER SOCKET] JOIN ROOM: ${room} by socketId=${socket.id} (UserId: ${userId})`);

    if (userId) {
      const userRoom = `user_${userId}`;
      socket.join(userRoom);
      socket.data.userId = userId;

      pool.query("UPDATE users SET is_online = true WHERE id = $1", [userId]).catch(() => {});

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
      const { conversationId, message, attachmentUrl, attachmentType, attachmentName, attachmentSize, replyToMessageId, messageId, isAlreadySaved, tempMsgId, nonce, isEncrypted } = data;
      // Derive sender identity strictly from authenticated socket JWT
      const senderId = socket.user?.userId || socket.data?.userId;
      console.log(`[SERVER SOCKET] sendMessage RECEIVED:`, { conversationId, senderId, message });

      if (!conversationId || !senderId || (!message && !attachmentUrl)) {
        console.error("Invalid message payload:", data);
        return;
      }

      // Verify conversation membership for senderId
      const memberCheck = await pool.query(
        "SELECT 1 FROM conversation_members WHERE conversation_id = $1 AND user_id = $2",
        [conversationId, senderId]
      );
      if (memberCheck.rows.length === 0) {
        console.warn(`Unauthorized sendMessage attempt by user ${senderId} in conversation ${conversationId}`);
        return;
      }

      let newMessage;

      if (messageId || isAlreadySaved) {
        // Message was already saved to DB by /messages/upload endpoint!
        const existingRes = await pool.query(
          `SELECT id, conversation_id, sender_id, message, attachment_url, attachment_type, attachment_name, attachment_size, reply_to_message_id, nonce, is_encrypted, is_delivered, is_read, is_edited, is_deleted, reactions, created_at
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
          `INSERT INTO messages (conversation_id, sender_id, message, attachment_url, attachment_type, attachment_name, attachment_size, reply_to_message_id, nonce, is_encrypted, is_delivered, is_read)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, false, false)
           RETURNING id, conversation_id, sender_id, message, attachment_url, attachment_type, attachment_name, attachment_size, reply_to_message_id, nonce, is_encrypted, is_delivered, is_read, is_edited, is_deleted, reactions, created_at`,
          [conversationId, senderId, message || "", attachmentUrl || null, attachmentType || null, attachmentName || null, attachmentSize || null, replyToMessageId || null, nonce || null, isEncrypted !== undefined ? isEncrypted : true]
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
      console.log(`[SERVER SOCKET] MESSAGE SAVED:`, newMessage.id);

      const room = String(conversationId);
      const recipientId = Number(senderId) === 1 ? 2 : 1;

      // Emit to the SENDER with is_mine:true (they sent this message)
      socket.emit("newMessage", { ...newMessage, is_mine: true });

      // Emit to RECIPIENT socket(s) with is_mine:false (they received this message)
      io.to(`user_${recipientId}`).emit("newMessage", { ...newMessage, is_mine: false });

      // Also emit to other sockets of the sender (multi-tab) with is_mine:true
      socket.to(`user_${senderId}`).emit("newMessage", { ...newMessage, is_mine: true });

      console.log(`newMessage emitted: sender=${senderId}(is_mine:true) recipient=${recipientId}(is_mine:false)`);
      console.log(`[SERVER SOCKET] EMITTING newMessage TO ROOM: ${room}`);
      
      const roomSocketsSet = io.sockets.adapter.rooms.get(room);
      console.log(`[SERVER SOCKET] ROOM MEMBERS for ${room}:`, roomSocketsSet ? Array.from(roomSocketsSet) : []);

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

        // Send generic privacy-preserving push notification (never leaking private text)
        await sendPushNotification({
          recipientId,
          title: "DuoChat",
          body: "New message",
          dataPayload: {
            conversationId: String(conversationId),
            senderId: String(senderId),
            type: "message",
          },
        });
      }
    } catch (error) {
      console.error("Error saving/broadcasting message:", error.message);
    }
  });

  // Mark Messages Delivered Event
  socket.on("markMessagesDelivered", async (data) => {
    try {
      const { conversationId } = data || {};
      const userId = socket.user?.userId || socket.data?.userId;
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
      const { conversationId } = data || {};
      const userId = socket.user?.userId || socket.data?.userId;
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
      const { conversationId, messageId, emoji } = data || {};
      const userId = socket.user?.userId || socket.data?.userId;
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

  // Typing Event (Validated against authenticated JWT identity & conversation membership)
  socket.on("typing", async (data) => {
    try {
      const { conversationId } = data || {};
      const senderId = socket.user?.userId || socket.data?.userId;
      if (!conversationId || !senderId) return;

      const memberCheck = await pool.query(
        "SELECT 1 FROM conversation_members WHERE conversation_id = $1 AND user_id = $2",
        [conversationId, senderId]
      );
      if (memberCheck.rows.length === 0) return;

      const recipientId = Number(senderId) === 1 ? 2 : 1;
      const userName = Number(senderId) === 1 ? "User 1" : "User 2";
      io.to(`user_${recipientId}`).emit("typing", {
        conversationId: Number(conversationId),
        senderId: Number(senderId),
        userName,
      });
    } catch (err) {
      console.error("Error handling typing event:", err.message);
    }
  });

  // Stop Typing Event
  socket.on("stopTyping", async (data) => {
    try {
      const { conversationId } = data || {};
      const senderId = socket.user?.userId || socket.data?.userId;
      if (!conversationId || !senderId) return;

      const recipientId = Number(senderId) === 1 ? 2 : 1;
      const userName = Number(senderId) === 1 ? "User 1" : "User 2";
      io.to(`user_${recipientId}`).emit("stopTyping", {
        conversationId: Number(conversationId),
        senderId: Number(senderId),
        userName,
      });
    } catch (err) {
      console.error("Error handling stopTyping event:", err.message);
    }
  });

  // Instagram Vanish Mode Toggle Event
  socket.on("toggleVanishMode", (data) => {
    const { conversationId, isVanishMode, senderId } = data || {};
    const room = String(conversationId);
    console.log(`Vanish mode toggled in room ${room} to ${isVanishMode} by user ${senderId} 🔮`);
    io.to(room).emit("vanishModeToggle", { conversationId, isVanishMode, senderId });
  });

  // ==================================================
  // PHASE 4: WEBRTC 1-TO-1 CALL SIGNALING HANDLERS
  // ==================================================

  socket.on("callUser", async (data) => {
    try {
      const { conversationId, isVideoCall, callerName } = data || {};
      const callerId = socket.user?.userId || socket.data?.userId;

      if (!conversationId || !callerId) {
        return socket.emit("callError", { message: "Invalid call payload" });
      }

      const memberCheck = await pool.query(
        "SELECT 1 FROM conversation_members WHERE conversation_id = $1 AND user_id = $2",
        [conversationId, callerId]
      );
      if (memberCheck.rows.length === 0) {
        return socket.emit("callError", { message: "Not authorized in this conversation" });
      }

      if (activeCalls.has(String(conversationId))) {
        return socket.emit("callError", { message: "Call already in progress in this conversation" });
      }

      const recipientId = Number(callerId) === 1 ? 2 : 1;
      activeCalls.set(String(conversationId), {
        callerId: Number(callerId),
        recipientId: Number(recipientId),
        isVideoCall: !!isVideoCall,
        status: "calling",
      });

      console.log(`Call initiated by User ${callerId} to User ${recipientId} in conversation ${conversationId} (Video: ${!!isVideoCall}) 📞`);

      io.to(`user_${recipientId}`).emit("incomingCall", {
        conversationId: Number(conversationId),
        callerId: Number(callerId),
        callerName: callerName || (Number(callerId) === 1 ? "User 1" : "User 2"),
        isVideoCall: !!isVideoCall,
      });

      // Send generic call push notification if recipient is backgrounded/offline
      const roomSockets = io.sockets.adapter.rooms.get(String(conversationId));
      let isRecipientActiveInRoom = false;
      if (roomSockets) {
        for (const socketId of roomSockets) {
          const s = io.sockets.sockets.get(socketId);
          if (s && s.data && s.data.userId && Number(s.data.userId) === Number(recipientId)) {
            isRecipientActiveInRoom = true;
            break;
          }
        }
      }

      if (!isRecipientActiveInRoom) {
        await sendPushNotification({
          recipientId,
          title: "DuoChat",
          body: isVideoCall ? "Incoming Video Call" : "Incoming Audio Call",
          dataPayload: {
            conversationId: String(conversationId),
            callerId: String(callerId),
            type: "call",
            isVideoCall: String(!!isVideoCall),
          },
        });
      }
    } catch (err) {
      console.error("Error in callUser socket event:", err.message);
    }
  });

  socket.on("acceptCall", async (data) => {
    try {
      const { conversationId } = data || {};
      const userId = socket.user?.userId || socket.data?.userId;
      if (!conversationId || !userId) return;

      const call = activeCalls.get(String(conversationId));
      if (call) {
        call.status = "active";
        console.log(`Call accepted by User ${userId} in conversation ${conversationId} ✅`);
        io.to(`user_${call.callerId}`).emit("callAccepted", {
          conversationId: Number(conversationId),
          acceptedBy: Number(userId),
        });
      }
    } catch (err) {
      console.error("Error in acceptCall socket event:", err.message);
    }
  });

  socket.on("rejectCall", (data) => {
    try {
      const { conversationId, reason } = data || {};
      const userId = socket.user?.userId || socket.data?.userId;
      const call = activeCalls.get(String(conversationId));
      if (call) {
        console.log(`Call rejected by User ${userId} in conversation ${conversationId} ❌`);
        io.to(`user_${call.callerId}`).emit("callRejected", {
          conversationId: Number(conversationId),
          rejectedBy: Number(userId),
          reason: reason || "declined",
        });
        activeCalls.delete(String(conversationId));
      }
    } catch (err) {
      console.error("Error in rejectCall socket event:", err.message);
    }
  });

  socket.on("cancelCall", (data) => {
    try {
      const { conversationId } = data || {};
      const userId = socket.user?.userId || socket.data?.userId;
      const call = activeCalls.get(String(conversationId));
      if (call && Number(call.callerId) === Number(userId)) {
        console.log(`Call cancelled by caller User ${userId} in conversation ${conversationId} 🚫`);
        io.to(`user_${call.recipientId}`).emit("callCancelled", {
          conversationId: Number(conversationId),
          cancelledBy: Number(userId),
        });
        activeCalls.delete(String(conversationId));
      }
    } catch (err) {
      console.error("Error in cancelCall socket event:", err.message);
    }
  });

  socket.on("webrtcOffer", async (data) => {
    try {
      const { conversationId, sdp } = data || {};
      const senderId = socket.user?.userId || socket.data?.userId;
      if (!conversationId || !senderId || !sdp) return;

      const memberCheck = await pool.query(
        "SELECT 1 FROM conversation_members WHERE conversation_id = $1 AND user_id = $2",
        [conversationId, senderId]
      );
      if (memberCheck.rows.length === 0) return;

      const recipientId = Number(senderId) === 1 ? 2 : 1;
      io.to(`user_${recipientId}`).emit("webrtcOffer", {
        conversationId: Number(conversationId),
        sdp,
        senderId: Number(senderId),
      });
    } catch (err) {
      console.error("Error in webrtcOffer:", err.message);
    }
  });

  socket.on("webrtcAnswer", async (data) => {
    try {
      const { conversationId, sdp } = data || {};
      const senderId = socket.user?.userId || socket.data?.userId;
      if (!conversationId || !senderId || !sdp) return;

      const memberCheck = await pool.query(
        "SELECT 1 FROM conversation_members WHERE conversation_id = $1 AND user_id = $2",
        [conversationId, senderId]
      );
      if (memberCheck.rows.length === 0) return;

      const recipientId = Number(senderId) === 1 ? 2 : 1;
      io.to(`user_${recipientId}`).emit("webrtcAnswer", {
        conversationId: Number(conversationId),
        sdp,
        senderId: Number(senderId),
      });
    } catch (err) {
      console.error("Error in webrtcAnswer:", err.message);
    }
  });

  socket.on("webrtcIceCandidate", async (data) => {
    try {
      const { conversationId, candidate } = data || {};
      const senderId = socket.user?.userId || socket.data?.userId;
      if (!conversationId || !senderId || !candidate) return;

      const memberCheck = await pool.query(
        "SELECT 1 FROM conversation_members WHERE conversation_id = $1 AND user_id = $2",
        [conversationId, senderId]
      );
      if (memberCheck.rows.length === 0) return;

      const recipientId = Number(senderId) === 1 ? 2 : 1;
      io.to(`user_${recipientId}`).emit("webrtcIceCandidate", {
        conversationId: Number(conversationId),
        candidate,
        senderId: Number(senderId),
      });
    } catch (err) {
      console.error("Error in webrtcIceCandidate:", err.message);
    }
  });

  socket.on("endCall", (data) => {
    try {
      const { conversationId } = data || {};
      const senderId = socket.user?.userId || socket.data?.userId;
      if (!conversationId) return;

      activeCalls.delete(String(conversationId));
      const recipientId = Number(senderId) === 1 ? 2 : 1;
      io.to(`user_${recipientId}`).to(String(conversationId)).emit("callEnded", {
        conversationId: Number(conversationId),
        endedBy: Number(senderId),
      });
      console.log(`Call ended by User ${senderId} in conversation ${conversationId} ⏹️`);
    } catch (err) {
      console.error("Error in endCall socket event:", err.message);
    }
  });

  socket.on("disconnect", async () => {
    console.log(`Socket disconnected: ${socket.id}`);
    const userId = socket.user?.userId || socket.user?.id || socket.data?.userId;

    if (userId && userSockets.has(Number(userId))) {
      const socketSet = userSockets.get(Number(userId));
      socketSet.delete(socket.id);

      if (socketSet.size === 0) {
        userSockets.delete(Number(userId));
        const lastSeenAt = new Date().toISOString();

        try {
          await pool.query("UPDATE users SET is_online = false, last_seen_at = NOW() WHERE id = $1", [userId]);
        } catch (err) {
          console.error("Error updating last_seen_at:", err.message);
        }

        const recipientId = Number(userId) === 1 ? 2 : 1;
        io.to(`user_${recipientId}`).emit("userOffline", {
          conversationId: 1,
          userId: Number(userId),
          lastSeenAt: lastSeenAt,
        });
        console.log(`User ${userId} went OFFLINE (last socket disconnected) at ${lastSeenAt} 🔴`);
      } else {
        console.log(`User ${userId} disconnected 1 socket (${socketSet.size} remaining active)`);
      }
    }
  });
});

// Global Production Error Handling Middleware (No stack traces or path leaks)
app.use((err, req, res, next) => {
  console.error("Unhandled Error:", err.message);
  res.status(err.status || 500).json({
    success: false,
    message: err.message && process.env.NODE_ENV === "development" ? err.message : "An internal server error occurred",
  });
});

const PORT = process.env.PORT || 5000;

// Strict 2-User Database Seeding
async function enforcePrivateTwoUserApp() {
  const email1 = (process.env.DUO_USER1_EMAIL || "user1@duochat.local").trim().toLowerCase();
  const email2 = (process.env.DUO_USER2_EMAIL || "user2@duochat.local").trim().toLowerCase();

  console.log("[DB SEED] Enforcing strict 2-user private mode...");

  // Each step isolated — one failure won't block others
  try {
    await pool.query(
      `INSERT INTO users (id, name, email, password_hash)
       VALUES (1, 'User 1', $1, 'LOCKED_NO_LOGIN')
       ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email`,
      [email1]
    );
    console.log("[DB SEED] User 1 OK ✅");
  } catch (e) { console.error("[DB SEED] User 1 error:", e.message); }

  try {
    await pool.query(
      `INSERT INTO users (id, name, email, password_hash)
       VALUES (2, 'User 2', $1, 'LOCKED_NO_LOGIN')
       ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email`,
      [email2]
    );
    console.log("[DB SEED] User 2 OK ✅");
  } catch (e) { console.error("[DB SEED] User 2 error:", e.message); }

  try {
    // conversations table has only: id, created_at — no type column
    await pool.query(
      `INSERT INTO conversations (id) VALUES (1) ON CONFLICT (id) DO NOTHING`
    );
    console.log("[DB SEED] Conversation OK ✅");
  } catch (e) { console.error("[DB SEED] Conversation error:", e.message); }

  try {
    await pool.query(
      `INSERT INTO conversation_members (conversation_id, user_id) VALUES (1, 1) ON CONFLICT DO NOTHING`
    );
    await pool.query(
      `INSERT INTO conversation_members (conversation_id, user_id) VALUES (1, 2) ON CONFLICT DO NOTHING`
    );
    console.log("[DB SEED] Conversation members OK ✅");
  } catch (e) { console.error("[DB SEED] Conv members error:", e.message); }

  console.log("[DB SEED] Setup complete.");
}

enforcePrivateTwoUserApp().then(() => {
  server.listen(PORT, () => {
    console.log(`DuoChat server running on port ${PORT}`);
  });
});