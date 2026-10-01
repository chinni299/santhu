require("dotenv").config();
const express = require("express");
const http = require("http");
const { Server } = require("socket.io");
const jwt = require("jsonwebtoken");
const authRoutes = require("./auth");
const messageRoutes = require("./messages");
const cors = require("cors");
const { registerHeartbeatHandlers } = require("./heartbeat_handler");
const { registerFingerTrailHandlers } = require("./finger_trail_handler");
const { sharedSkyRouter, registerSharedSkyHandlers } = require("./shared_sky_handler");
const { hugKissRouter, registerHugKissHandlers } = require("./hug_kiss_handler");

const pool = require("./db");
const { redis, isRedisEnabled } = require("./redisClient");
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
app.use("/shared-sky", sharedSkyRouter);
app.use("/hug-kiss", hugKissRouter);

console.log("MESSAGES, SHARED SKY & HUG-KISS API REGISTERED ✅");

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
// NEW: Global registry of pending ring-timeout timers -> conversationId -> Timeout handle
const callRingTimeouts = new Map();
// Global active user socket connections registry: userId -> Set<socketId>
const userSockets = new Map();

// NEW: Nudge cooldown registry — conversationId -> last-nudge timestamp (ms)
const nudgeCooldowns = new Map();
const NUDGE_COOLDOWN_MS = 3000; // 3 seconds between nudges per conversation

// NEW: How long (ms) an outgoing call rings before being auto-cancelled as "missed"
const CALL_RING_TIMEOUT_MS = 45000;

// ==================================================
// REDIS-BACKED PRESENCE TRACKING (restart-safe online/offline)
// ==================================================
// Why: userSockets (above) is an in-memory Map that resets to empty on every
// server restart/redeploy. If the process crashes or is redeployed while a
// user is connected, the socket "disconnect" handler never runs, so Postgres
// is left showing that user as permanently online ("ghost online").
//
// Fix: each connected user's presence is mirrored into Redis as a key with a
// short TTL (PRESENCE_TTL_SECONDS). While connected, a heartbeat refreshes
// that TTL periodically. Redis itself survives app restarts/redeploys (it's
// a separate managed process), so a reconciliation job can compare "who
// Postgres thinks is online" against "whose presence key is still alive in
// Redis" and correct any stale rows automatically — even after a crash.
const PRESENCE_TTL_SECONDS = 30; // presence key expires if not refreshed within this window
const PRESENCE_HEARTBEAT_MS = 15000; // refresh well before the TTL expires
const PRESENCE_RECONCILE_MS = 20000; // how often to sweep for stale "online" rows

function presenceKey(userId) {
  return `duochat:presence:${userId}`;
}

async function markUserPresentInRedis(userId) {
  if (!isRedisEnabled()) return;
  try {
    await redis.set(presenceKey(userId), Date.now().toString(), "EX", PRESENCE_TTL_SECONDS);
  } catch (err) {
    console.error(`Redis presence SET error for user ${userId}:`, err.message);
  }
}

async function clearUserPresenceInRedis(userId) {
  if (!isRedisEnabled()) return;
  try {
    await redis.del(presenceKey(userId));
  } catch (err) {
    console.error(`Redis presence DEL error for user ${userId}:`, err.message);
  }
}

async function isUserPresentInRedis(userId) {
  if (!isRedisEnabled()) return null; // null = "unknown, Redis not available"
  try {
    const val = await redis.get(presenceKey(userId));
    return val !== null;
  } catch (err) {
    console.error(`Redis presence GET error for user ${userId}:`, err.message);
    return null;
  }
}

// Reconciliation sweep: for our strict 2-user app (ids 1 and 2), if Postgres
// says a user is online but their Redis presence key has expired/missing
// (meaning no server process has heartbeated for them recently), correct
// Postgres and notify the other user. This heals "ghost online" after a
// crash or redeploy, without needing any manual intervention.
async function reconcilePresenceWithRedis() {
  if (!isRedisEnabled()) return; // nothing to reconcile without Redis
  try {
    const dbRes = await pool.query("SELECT id, is_online FROM users WHERE id IN (1, 2)");
    for (const row of dbRes.rows) {
      if (!row.is_online) continue;
      const stillPresent = await isUserPresentInRedis(row.id);
      // Also trust a live in-memory socket (covers the case where Redis
      // itself briefly hiccups but the socket is genuinely still connected).
      const hasLiveSocket = userSockets.has(Number(row.id)) && userSockets.get(Number(row.id)).size > 0;

      if (stillPresent === false && !hasLiveSocket) {
        const lastSeenAt = new Date().toISOString();
        await pool.query("UPDATE users SET is_online = false, last_seen_at = NOW() WHERE id = $1", [row.id]);
        const recipientId = Number(row.id) === 1 ? 2 : 1;
        io.to(`user_${recipientId}`).emit("userOffline", {
          conversationId: 1,
          userId: Number(row.id),
          lastSeenAt,
        });
        console.log(`[PRESENCE RECONCILE] Corrected stale ONLINE status for User ${row.id} → OFFLINE 🩹`);
      }
    }
  } catch (err) {
    console.error("Presence reconciliation error:", err.message);
  }
}

// NEW: Helper to clear any pending ring-timeout for a conversation
function clearCallRingTimeout(conversationId) {
  const key = String(conversationId);
  const existing = callRingTimeouts.get(key);
  if (existing) {
    clearTimeout(existing);
    callRingTimeouts.delete(key);
  }
}

// ==================================================
// DISAPPEARING MESSAGES — background sweep for expired messages
// ==================================================
const DISAPPEARING_SWEEP_MS = 30000; // check every 30 seconds

async function sweepExpiredMessages() {
  try {
    const liveRes = await pool.query(
      `UPDATE messages
       SET live_location_active = false
       WHERE live_location_active = true AND live_location_expires_at IS NOT NULL AND live_location_expires_at <= NOW()
       RETURNING id, conversation_id`
    );
    for (const row of liveRes.rows) {
      io.to(String(row.conversation_id)).emit("liveLocationEnded", {
        conversationId: Number(row.conversation_id),
        messageId: Number(row.id),
      });
    }
    if (liveRes.rowCount > 0) {
      console.log(`[LIVE LOCATION SWEEP] Ended ${liveRes.rowCount} expired live share(s) 📍⏱️`);
    }
  } catch (err) {
    console.error("Live-location sweep error:", err.message);
  }

  // --- Disappearing messages ---
  try {
    const result = await pool.query(
      `UPDATE messages
       SET is_deleted = true, message = 'This message was deleted'
       WHERE expires_at IS NOT NULL AND expires_at <= NOW() AND is_deleted = false
       RETURNING id, conversation_id, sender_id`
    );

    if (result.rowCount > 0) {
      for (const row of result.rows) {
        const room = String(row.conversation_id);
        io.to(room).emit("messageDeleted", {
          conversationId: row.conversation_id,
          messageId: Number(row.id),
          senderId: row.sender_id,
          isDeleted: true,
          reason: "expired",
        });
      }
      console.log(`[DISAPPEARING SWEEP] Auto-deleted ${result.rowCount} expired message(s) ⏳🗑️`);
    }
  } catch (err) {
    console.error("Disappearing-messages sweep error:", err.message);
  }
}

// ==================================================
// SCHEDULED MESSAGES — background sweep to send due messages
// ==================================================
const SCHEDULED_SWEEP_MS = 20000; // check every 20 seconds

async function sweepDueScheduledMessages() {
  try {
    const dueRes = await pool.query(
      `SELECT id, conversation_id, sender_id, message
       FROM scheduled_messages
       WHERE is_sent = false AND is_cancelled = false AND send_at <= NOW()
       ORDER BY send_at ASC
       LIMIT 50`
    );

    for (const sched of dueRes.rows) {
      try {
        // Resolve the conversation's active disappearing-messages timer, same
        // as any other message sent right now would.
        let expiresAt = null;
        const convRes = await pool.query(
          "SELECT disappearing_timer_seconds FROM conversations WHERE id = $1",
          [sched.conversation_id]
        );
        const timerSeconds = convRes.rows[0]?.disappearing_timer_seconds;
        if (timerSeconds && Number(timerSeconds) > 0) {
          expiresAt = new Date(Date.now() + Number(timerSeconds) * 1000);
        }

        const insertRes = await pool.query(
          `INSERT INTO messages (conversation_id, sender_id, message, is_delivered, is_read, expires_at)
           VALUES ($1, $2, $3, false, false, $4)
           RETURNING id, conversation_id, sender_id, message, attachment_url, attachment_type, attachment_name, attachment_size, reply_to_message_id, nonce, is_encrypted, is_delivered, is_read, is_edited, is_deleted, reactions, expires_at, created_at`,
          [sched.conversation_id, sched.sender_id, sched.message, expiresAt]
        );
        const newMessage = insertRes.rows[0];

        await pool.query("UPDATE scheduled_messages SET is_sent = true WHERE id = $1", [sched.id]);

        const recipientId = Number(sched.sender_id) === 1 ? 2 : 1;
        io.to(`user_${sched.sender_id}`).emit("newMessage", { ...newMessage, is_mine: true });
        io.to(`user_${recipientId}`).emit("newMessage", { ...newMessage, is_mine: false });

        console.log(`[SCHEDULED SWEEP] Sent scheduled message ${sched.id} in conversation ${sched.conversation_id} ⏰✅`);
      } catch (innerErr) {
        console.error(`Error sending scheduled message ${sched.id}:`, innerErr.message);
      }
    }
  } catch (err) {
    console.error("Scheduled-messages sweep error:", err.message);
  }
}

// ==================================================
// LIVE LOCATION — background sweep to auto-end expired live shares
// ==================================================
const LIVE_LOCATION_SWEEP_MS = 30000; // check every 30 seconds

async function sweepExpiredLiveLocations() {
  try {
    const result = await pool.query(
      `UPDATE messages
       SET live_location_active = false
       WHERE live_location_active = true
         AND live_location_expires_at IS NOT NULL
         AND live_location_expires_at <= NOW()
       RETURNING id, conversation_id`
    );

    if (result.rowCount > 0) {
      for (const row of result.rows) {
        const room = String(row.conversation_id);
        io.to(room).emit("liveLocationEnded", {
          conversationId: row.conversation_id,
          messageId: Number(row.id),
        });
      }
      console.log(`[LIVE LOCATION SWEEP] Auto-ended ${result.rowCount} expired live location share(s) 📍⏳`);
    }
  } catch (err) {
    console.error("Live-location sweep error:", err.message);
  }
}

// Socket.IO Connection Handler
io.on("connection", (socket) => {
  registerHeartbeatHandlers(io, socket, userSockets);
  registerFingerTrailHandlers(io, socket);
  registerSharedSkyHandlers(io, socket);
  registerHugKissHandlers(io, socket, userSockets);
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
      markUserPresentInRedis(numId); // NEW: mirror presence into Redis
      const recipientId = numId === 1 ? 2 : 1;
      io.to(`user_${recipientId}`).emit("userOnline", { userId: numId, conversationId: 1 });
      console.log(`User ${numId} is now ONLINE (1st socket: ${socket.id}) 🟢`);
    } else {
      console.log(`User ${numId} connected additional socket (${socket.id}, active sockets: ${socketSet.size})`);
    }

    // NEW: Heartbeat — refresh this user's Redis presence TTL periodically
    // while at least one of their sockets is connected. One interval per
    // socket is fine (cheap SET EX); it self-clears on this socket's disconnect.
    socket.data.presenceHeartbeat = setInterval(() => {
      markUserPresentInRedis(numId);
    }, PRESENCE_HEARTBEAT_MS);
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

    // NEW: sync this socket with the conversation's current disappearing-timer setting
    pool.query("SELECT disappearing_timer_seconds FROM conversations WHERE id = $1", [conversationId])
      .then((convRes) => {
        socket.emit("disappearingTimerUpdate", {
          conversationId: Number(conversationId),
          timerSeconds: convRes.rows[0]?.disappearing_timer_seconds || null,
          setBy: null,
        });
      })
      .catch((err) => console.error("Error syncing disappearing timer on join:", err.message));

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
          `SELECT id, conversation_id, sender_id, message, attachment_url, attachment_type, attachment_name, attachment_size, reply_to_message_id, nonce, is_encrypted, is_delivered, is_read, is_edited, is_deleted, reactions, expires_at, created_at
           FROM messages WHERE id = $1`,
          [messageId]
        );
        if (existingRes.rows.length > 0) {
          newMessage = existingRes.rows[0];
        }
      }

      if (!newMessage) {
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
          console.error("Error resolving disappearing timer:", timerErr.message);
        }

        // Save to PostgreSQL database
        const result = await pool.query(
          `INSERT INTO messages (conversation_id, sender_id, message, attachment_url, attachment_type, attachment_name, attachment_size, reply_to_message_id, nonce, is_encrypted, is_delivered, is_read, expires_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, false, false, $11)
           RETURNING id, conversation_id, sender_id, message, attachment_url, attachment_type, attachment_name, attachment_size, reply_to_message_id, nonce, is_encrypted, is_delivered, is_read, is_edited, is_deleted, reactions, expires_at, created_at`,
          [conversationId, senderId, message || "", attachmentUrl || null, attachmentType || null, attachmentName || null, attachmentSize || null, replyToMessageId || null, nonce || null, isEncrypted !== undefined ? isEncrypted : true, expiresAt]
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
          title: "Clock",
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

  // ==================================================
  // PINNED MESSAGES — only one pinned message per conversation at a time
  // ==================================================
  socket.on("pinMessage", async (data) => {
    try {
      const { conversationId, messageId } = data || {};
      const userId = socket.user?.userId || socket.data?.userId;
      if (!conversationId || !messageId || !userId) return;

      const memberCheck = await pool.query(
        "SELECT 1 FROM conversation_members WHERE conversation_id = $1 AND user_id = $2",
        [conversationId, userId]
      );
      if (memberCheck.rows.length === 0) return;

      const checkMsg = await pool.query(
        "SELECT id, is_deleted FROM messages WHERE id = $1 AND conversation_id = $2",
        [messageId, conversationId]
      );
      if (checkMsg.rows.length === 0 || checkMsg.rows[0].is_deleted) return;

      // Unpin any previously pinned message in this conversation first (single-pin model)
      await pool.query(
        "UPDATE messages SET is_pinned = false, pinned_by = NULL, pinned_at = NULL WHERE conversation_id = $1 AND is_pinned = true",
        [conversationId]
      );

      const result = await pool.query(
        `UPDATE messages
         SET is_pinned = true, pinned_by = $1, pinned_at = NOW()
         WHERE id = $2
         RETURNING id, conversation_id, sender_id, message, attachment_url, attachment_type, attachment_name, is_pinned, pinned_by, pinned_at`,
        [userId, messageId]
      );

      if (result.rowCount > 0) {
        const room = String(conversationId);
        io.to(room).emit("messagePinned", {
          conversationId: Number(conversationId),
          message: result.rows[0],
        });
        console.log(`Message ${messageId} pinned in conversation ${conversationId} by User ${userId} 📌`);
      }
    } catch (err) {
      console.error("Error in pinMessage socket event:", err.message);
    }
  });

  socket.on("unpinMessage", async (data) => {
    try {
      const { conversationId, messageId } = data || {};
      const userId = socket.user?.userId || socket.data?.userId;
      if (!conversationId || !userId) return;

      const memberCheck = await pool.query(
        "SELECT 1 FROM conversation_members WHERE conversation_id = $1 AND user_id = $2",
        [conversationId, userId]
      );
      if (memberCheck.rows.length === 0) return;

      await pool.query(
        "UPDATE messages SET is_pinned = false, pinned_by = NULL, pinned_at = NULL WHERE conversation_id = $1 AND is_pinned = true",
        [conversationId]
      );

      const room = String(conversationId);
      io.to(room).emit("messageUnpinned", {
        conversationId: Number(conversationId),
        messageId: messageId ? Number(messageId) : null,
      });
      console.log(`Pinned message cleared in conversation ${conversationId} by User ${userId} 📌`);
    } catch (err) {
      console.error("Error in unpinMessage socket event:", err.message);
    }
  });

  // ==================================================
  // LIVE LOCATION SHARING
  // ==================================================
  socket.on("shareLiveLocation", async (data) => {
    try {
      const { conversationId, latitude, longitude, durationSeconds } = data || {};
      const senderId = socket.user?.userId || socket.data?.userId;
      if (!conversationId || !senderId || latitude == null || longitude == null) return;

      const memberCheck = await pool.query(
        "SELECT 1 FROM conversation_members WHERE conversation_id = $1 AND user_id = $2",
        [conversationId, senderId]
      );
      if (memberCheck.rows.length === 0) return;

      const isLive = durationSeconds && Number(durationSeconds) > 0;
      const liveExpiresAt = isLive ? new Date(Date.now() + Number(durationSeconds) * 1000) : null;
      const payload = JSON.stringify({ lat: Number(latitude), lng: Number(longitude), isLive: !!isLive });

      const result = await pool.query(
        `INSERT INTO messages (conversation_id, sender_id, message, attachment_type, is_delivered, is_read, live_location_active, live_location_expires_at)
         VALUES ($1, $2, $3, 'location', false, false, $4, $5)
         RETURNING id, conversation_id, sender_id, message, attachment_type, is_delivered, is_read, is_edited, is_deleted, live_location_active, live_location_expires_at, created_at`,
        [conversationId, senderId, payload, !!isLive, liveExpiresAt]
      );

      const newMessage = result.rows[0];
      const room = String(conversationId);
      const recipientId = Number(senderId) === 1 ? 2 : 1;

      socket.emit("newMessage", { ...newMessage, is_mine: true });
      io.to(`user_${recipientId}`).emit("newMessage", { ...newMessage, is_mine: false });

      console.log(`User ${senderId} shared ${isLive ? "LIVE" : "current"} location in conversation ${conversationId} 📍`);

      if (!isLive) return; // one-time location share — nothing further to track

      // Notify recipient with a push if they're not actively in the room
      const roomSockets = io.sockets.adapter.rooms.get(room);
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
          title: "Clock",
          body: "Started sharing live location",
          dataPayload: { conversationId: String(conversationId), type: "live_location" },
        });
      }
    } catch (err) {
      console.error("Error in shareLiveLocation socket event:", err.message);
    }
  });

  socket.on("updateLiveLocation", async (data) => {
    try {
      const { conversationId, messageId, latitude, longitude } = data || {};
      const senderId = socket.user?.userId || socket.data?.userId;
      if (!conversationId || !messageId || !senderId || latitude == null || longitude == null) return;

      const checkMsg = await pool.query(
        "SELECT sender_id, live_location_active FROM messages WHERE id = $1",
        [messageId]
      );
      if (checkMsg.rows.length === 0) return;
      if (String(checkMsg.rows[0].sender_id) !== String(senderId)) return;
      if (!checkMsg.rows[0].live_location_active) return; // sharing already ended/expired

      const payload = JSON.stringify({ lat: Number(latitude), lng: Number(longitude), isLive: true });
      await pool.query("UPDATE messages SET message = $1 WHERE id = $2", [payload, messageId]);

      const room = String(conversationId);
      io.to(room).emit("liveLocationUpdate", {
        conversationId: Number(conversationId),
        messageId: Number(messageId),
        latitude: Number(latitude),
        longitude: Number(longitude),
      });
    } catch (err) {
      console.error("Error in updateLiveLocation socket event:", err.message);
    }
  });

  socket.on("stopLiveLocation", async (data) => {
    try {
      const { conversationId, messageId } = data || {};
      const senderId = socket.user?.userId || socket.data?.userId;
      if (!conversationId || !messageId || !senderId) return;

      const result = await pool.query(
        `UPDATE messages SET live_location_active = false
         WHERE id = $1 AND sender_id = $2
         RETURNING id`,
        [messageId, senderId]
      );

      if (result.rowCount > 0) {
        const room = String(conversationId);
        io.to(room).emit("liveLocationEnded", {
          conversationId: Number(conversationId),
          messageId: Number(messageId),
        });
        console.log(`Live location sharing ended for message ${messageId} in conversation ${conversationId} 📍🛑`);
      }
    } catch (err) {
      console.error("Error in stopLiveLocation socket event:", err.message);
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
  // DISAPPEARING MESSAGES — set / broadcast the per-conversation timer
  // ==================================================
  socket.on("setDisappearingTimer", async (data) => {
    try {
      const { conversationId, timerSeconds } = data || {};
      const senderId = socket.user?.userId || socket.data?.userId;
      if (!conversationId || !senderId) return;

      const memberCheck = await pool.query(
        "SELECT 1 FROM conversation_members WHERE conversation_id = $1 AND user_id = $2",
        [conversationId, senderId]
      );
      if (memberCheck.rows.length === 0) return;

      // 0 or null/undefined means "Off"
      const normalizedSeconds = timerSeconds && Number(timerSeconds) > 0 ? Number(timerSeconds) : null;

      await pool.query(
        "UPDATE conversations SET disappearing_timer_seconds = $1 WHERE id = $2",
        [normalizedSeconds, conversationId]
      );

      const room = String(conversationId);
      io.to(room).emit("disappearingTimerUpdate", {
        conversationId: Number(conversationId),
        timerSeconds: normalizedSeconds,
        setBy: Number(senderId),
      });
      console.log(`Disappearing timer for conversation ${conversationId} set to ${normalizedSeconds ?? "Off"} by User ${senderId} ⏳`);
    } catch (err) {
      console.error("Error in setDisappearingTimer socket event:", err.message);
    }
  });

  socket.on("getDisappearingTimer", async (data) => {
    try {
      const { conversationId } = data || {};
      if (!conversationId) return;
      const result = await pool.query(
        "SELECT disappearing_timer_seconds FROM conversations WHERE id = $1",
        [conversationId]
      );
      socket.emit("disappearingTimerUpdate", {
        conversationId: Number(conversationId),
        timerSeconds: result.rows[0]?.disappearing_timer_seconds || null,
        setBy: null,
      });
    } catch (err) {
      console.error("Error in getDisappearingTimer socket event:", err.message);
    }
  });

  // ==================================================
  // SCHEDULED MESSAGES
  // ==================================================
  socket.on("scheduleMessage", async (data) => {
    try {
      const { conversationId, message, sendAtIso } = data || {};
      const senderId = socket.user?.userId || socket.data?.userId;
      if (!conversationId || !senderId || !message || !sendAtIso) return;

      const memberCheck = await pool.query(
        "SELECT 1 FROM conversation_members WHERE conversation_id = $1 AND user_id = $2",
        [conversationId, senderId]
      );
      if (memberCheck.rows.length === 0) return;

      const sendAt = new Date(sendAtIso);
      if (isNaN(sendAt.getTime()) || sendAt.getTime() <= Date.now()) {
        return socket.emit("scheduleMessageError", { message: "Scheduled time must be in the future" });
      }

      const result = await pool.query(
        `INSERT INTO scheduled_messages (conversation_id, sender_id, message, send_at)
         VALUES ($1, $2, $3, $4)
         RETURNING id, conversation_id, sender_id, message, send_at, is_sent, is_cancelled, created_at`,
        [conversationId, senderId, message, sendAt]
      );

      socket.emit("scheduledMessageCreated", { scheduled: result.rows[0] });
      console.log(`Message scheduled by User ${senderId} in conversation ${conversationId} for ${sendAt.toISOString()} ⏰`);
    } catch (err) {
      console.error("Error in scheduleMessage socket event:", err.message);
    }
  });

  socket.on("cancelScheduledMessage", async (data) => {
    try {
      const { id } = data || {};
      const senderId = socket.user?.userId || socket.data?.userId;
      if (!id || !senderId) return;

      const result = await pool.query(
        `UPDATE scheduled_messages
         SET is_cancelled = true
         WHERE id = $1 AND sender_id = $2 AND is_sent = false
         RETURNING id`,
        [id, senderId]
      );

      if (result.rowCount > 0) {
        socket.emit("scheduledMessageCancelled", { id: Number(id) });
        console.log(`Scheduled message ${id} cancelled by User ${senderId} ⏰❌`);
      }
    } catch (err) {
      console.error("Error in cancelScheduledMessage socket event:", err.message);
    }
  });

  // ==================================================
  // SHARED COUNTDOWN / ANNIVERSARY TRACKER
  // ==================================================
  socket.on("addSpecialDate", async (data) => {
    try {
      const { conversationId, title, eventDate, isRecurringYearly } = data || {};
      const userId = socket.user?.userId || socket.data?.userId;
      if (!conversationId || !userId || !title || !eventDate) return;

      const memberCheck = await pool.query(
        "SELECT 1 FROM conversation_members WHERE conversation_id = $1 AND user_id = $2",
        [conversationId, userId]
      );
      if (memberCheck.rows.length === 0) return;

      const result = await pool.query(
        `INSERT INTO special_dates (conversation_id, title, event_date, is_recurring_yearly, created_by)
         VALUES ($1, $2, $3, $4, $5)
         RETURNING id, conversation_id, title, event_date, is_recurring_yearly, created_by, created_at`,
        [conversationId, String(title).slice(0, 120), eventDate, isRecurringYearly !== false, userId]
      );

      const room = String(conversationId);
      io.to(room).emit("specialDateAdded", { conversationId: Number(conversationId), date: result.rows[0] });
      console.log(`Special date "${title}" added to conversation ${conversationId} by User ${userId} 🎉`);
    } catch (err) {
      console.error("Error in addSpecialDate socket event:", err.message);
    }
  });

  socket.on("deleteSpecialDate", async (data) => {
    try {
      const { conversationId, id } = data || {};
      const userId = socket.user?.userId || socket.data?.userId;
      if (!conversationId || !id || !userId) return;

      const memberCheck = await pool.query(
        "SELECT 1 FROM conversation_members WHERE conversation_id = $1 AND user_id = $2",
        [conversationId, userId]
      );
      if (memberCheck.rows.length === 0) return;

      await pool.query("DELETE FROM special_dates WHERE id = $1 AND conversation_id = $2", [id, conversationId]);

      const room = String(conversationId);
      io.to(room).emit("specialDateDeleted", { conversationId: Number(conversationId), id: Number(id) });
    } catch (err) {
      console.error("Error in deleteSpecialDate socket event:", err.message);
    }
  });

  // ==================================================
  // NUDGE / "THINKING OF YOU"
  // ==================================================
  socket.on("sendNudge", async (data) => {
    try {
      const { conversationId } = data || {};
      const senderId = socket.user?.userId || socket.data?.userId;
      if (!conversationId || !senderId) return;

      const memberCheck = await pool.query(
        "SELECT 1 FROM conversation_members WHERE conversation_id = $1 AND user_id = $2",
        [conversationId, senderId]
      );
      if (memberCheck.rows.length === 0) return;

      // Per-conversation cooldown so a nudge can't be spammed
      const cooldownKey = String(conversationId);
      const lastNudge = nudgeCooldowns.get(cooldownKey) || 0;
      const now = Date.now();
      if (now - lastNudge < NUDGE_COOLDOWN_MS) {
        return socket.emit("nudgeError", {
          message: "Please wait a moment before nudging again",
          retryAfterMs: NUDGE_COOLDOWN_MS - (now - lastNudge),
        });
      }
      nudgeCooldowns.set(cooldownKey, now);

      const recipientId = Number(senderId) === 1 ? 2 : 1;
      const room = String(conversationId);

      io.to(room).to(`user_${recipientId}`).emit("nudgeReceived", {
        conversationId: Number(conversationId),
        senderId: Number(senderId),
      });
      console.log(`User ${senderId} sent a nudge in conversation ${conversationId} 👋`);

      // Push notification if the recipient isn't actively viewing the chat
      const roomSockets = io.sockets.adapter.rooms.get(room);
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
          title: "Clock",
          body: "💌 Thinking of you",
          dataPayload: { conversationId: String(conversationId), type: "nudge" },
        });
      }
    } catch (err) {
      console.error("Error in sendNudge socket event:", err.message);
    }
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

      // NEW: Call History — create the log row up front, status starts "ringing"
      let callLogId = null;
      try {
        const logRes = await pool.query(
          `INSERT INTO call_logs (conversation_id, caller_id, recipient_id, is_video_call, status, started_at)
           VALUES ($1, $2, $3, $4, 'ringing', NOW())
           RETURNING id`,
          [conversationId, callerId, recipientId, !!isVideoCall]
        );
        callLogId = logRes.rows[0]?.id || null;
      } catch (logErr) {
        console.error("Error creating call_logs row:", logErr.message);
      }

      activeCalls.set(String(conversationId), {
        callerId: Number(callerId),
        recipientId: Number(recipientId),
        isVideoCall: !!isVideoCall,
        status: "calling",
        callLogId,
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
          title: "Clock",
          body: isVideoCall ? "Incoming Video Call" : "Incoming Audio Call",
          dataPayload: {
            conversationId: String(conversationId),
            callerId: String(callerId),
            type: "call",
            isVideoCall: String(!!isVideoCall),
          },
        });
      }

      // ==================================================
      // NEW: Auto-cancel ("missed call") if not answered within CALL_RING_TIMEOUT_MS
      // ==================================================
      clearCallRingTimeout(conversationId); // safety: clear any stale timer first
      const timeoutId = setTimeout(async () => {
        const stillRinging = activeCalls.get(String(conversationId));
        if (stillRinging && stillRinging.status === "calling") {
          activeCalls.delete(String(conversationId));
          callRingTimeouts.delete(String(conversationId));

          if (stillRinging.callLogId) {
            pool.query(
              "UPDATE call_logs SET status = 'missed', ended_at = NOW() WHERE id = $1",
              [stillRinging.callLogId]
            ).catch((e) => console.error("Error marking call_logs as missed:", e.message));
          }

          io.to(`user_${callerId}`).emit("callMissed", {
            conversationId: Number(conversationId),
          });
          io.to(`user_${recipientId}`).emit("callCancelled", {
            conversationId: Number(conversationId),
            reason: "timeout",
          });

          try {
            await sendPushNotification({
              recipientId: callerId,
              title: "Clock",
              body: "Missed Call",
              dataPayload: {
                conversationId: String(conversationId),
                type: "missed_call",
              },
            });
          } catch (pushErr) {
            console.error("Error sending missed-call push notification:", pushErr.message);
          }

          console.log(`Call in conversation ${conversationId} auto-cancelled (no answer within ${CALL_RING_TIMEOUT_MS / 1000}s) ⏱️`);
        }
      }, CALL_RING_TIMEOUT_MS);
      callRingTimeouts.set(String(conversationId), timeoutId);
    } catch (err) {
      console.error("Error in callUser socket event:", err.message);
    }
  });

  socket.on("acceptCall", async (data) => {
    try {
      const { conversationId } = data || {};
      const userId = socket.user?.userId || socket.data?.userId;
      if (!conversationId || !userId) return;

      // NEW: call was answered — cancel the pending ring-timeout
      clearCallRingTimeout(conversationId);

      const call = activeCalls.get(String(conversationId));
      if (call) {
        call.status = "active";
        console.log(`Call accepted by User ${userId} in conversation ${conversationId} ✅`);

        // NEW: Call History — mark as answered
        if (call.callLogId) {
          pool.query(
            "UPDATE call_logs SET status = 'answered', answered_at = NOW() WHERE id = $1",
            [call.callLogId]
          ).catch((e) => console.error("Error marking call_logs as answered:", e.message));
        }

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

      // NEW: call was explicitly rejected — cancel the pending ring-timeout
      clearCallRingTimeout(conversationId);

      const call = activeCalls.get(String(conversationId));
      if (call) {
        console.log(`Call rejected by User ${userId} in conversation ${conversationId} ❌`);

        // NEW: Call History — mark as declined
        if (call.callLogId) {
          pool.query(
            "UPDATE call_logs SET status = 'declined', ended_at = NOW() WHERE id = $1",
            [call.callLogId]
          ).catch((e) => console.error("Error marking call_logs as declined:", e.message));
        }

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

      // NEW: caller cancelled before answer — cancel the pending ring-timeout
      clearCallRingTimeout(conversationId);

      const call = activeCalls.get(String(conversationId));
      if (call && Number(call.callerId) === Number(userId)) {
        console.log(`Call cancelled by caller User ${userId} in conversation ${conversationId} 🚫`);

        // NEW: Call History — mark as cancelled
        if (call.callLogId) {
          pool.query(
            "UPDATE call_logs SET status = 'cancelled', ended_at = NOW() WHERE id = $1",
            [call.callLogId]
          ).catch((e) => console.error("Error marking call_logs as cancelled:", e.message));
        }

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

      // NEW: call ended — cancel any pending ring-timeout
      clearCallRingTimeout(conversationId);

      const call = activeCalls.get(String(conversationId));

      // NEW: Call History — compute final duration for an answered call.
      // ended_at IS NULL guards against a race where endCall fires twice.
      if (call && call.callLogId) {
        pool.query(
          `UPDATE call_logs
           SET ended_at = NOW(),
               duration_seconds = CASE WHEN answered_at IS NOT NULL THEN GREATEST(EXTRACT(EPOCH FROM (NOW() - answered_at))::int, 0) ELSE 0 END,
               status = CASE WHEN answered_at IS NOT NULL THEN 'answered' ELSE status END
           WHERE id = $1 AND ended_at IS NULL`,
          [call.callLogId]
        ).catch((e) => console.error("Error finalizing call_logs duration:", e.message));
      }

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

    // NEW: stop this socket's presence heartbeat
    if (socket.data.presenceHeartbeat) {
      clearInterval(socket.data.presenceHeartbeat);
      socket.data.presenceHeartbeat = null;
    }

    if (userId && userSockets.has(Number(userId))) {
      const socketSet = userSockets.get(Number(userId));
      socketSet.delete(socket.id);

      if (socketSet.size === 0) {
        userSockets.delete(Number(userId));
        const lastSeenAt = new Date().toISOString();

        await clearUserPresenceInRedis(userId); // NEW: drop Redis presence key immediately

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

server.listen(PORT, () => {
  console.log(`DuoChat server running on port ${PORT}`);
  enforcePrivateTwoUserApp().catch(err => {
    console.error("[DB SEED] Unhandled seed error:", err.message);
  });

  // NEW: Presence reconciliation — heals "ghost online" rows left behind by
  // a crash or redeploy (Postgres says online, but no live socket or Redis
  // heartbeat backs that up). No-op automatically if REDIS_URL isn't set.
  setInterval(reconcilePresenceWithRedis, PRESENCE_RECONCILE_MS);
  // Also run one pass shortly after boot, so a stale "online" row left by a
  // crash gets corrected quickly instead of waiting a full interval.
  setTimeout(reconcilePresenceWithRedis, 5000);

  // NEW: Disappearing messages — periodic sweep to auto-delete expired messages
  setInterval(sweepExpiredMessages, DISAPPEARING_SWEEP_MS);
  setTimeout(sweepExpiredMessages, 5000);

  // NEW: Live location — periodic sweep to auto-end expired live shares
  setInterval(sweepExpiredLiveLocations, LIVE_LOCATION_SWEEP_MS);
  setTimeout(sweepExpiredLiveLocations, 5000);

  // NEW: Scheduled messages — periodic sweep to send due messages
  setInterval(sweepDueScheduledMessages, SCHEDULED_SWEEP_MS);
  setTimeout(sweepDueScheduledMessages, 5000);
});