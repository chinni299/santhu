'use strict';

const express = require('express');
const pool = require('./db');
const { authenticateToken } = require('./middleware/authMiddleware');

// ── Database Table Initialization ───────────────────────────────────────────
pool.query(`
  CREATE TABLE IF NOT EXISTS pending_hugs (
    id SERIAL PRIMARY KEY,
    conversation_id INTEGER NOT NULL,
    sender_id INTEGER NOT NULL,
    sender_name VARCHAR(255),
    recipient_id INTEGER NOT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    is_delivered BOOLEAN DEFAULT false,
    delivered_at TIMESTAMPTZ
  );
  CREATE INDEX IF NOT EXISTS idx_pending_hugs_recipient ON pending_hugs(recipient_id, is_delivered);
`).then(() => {
  console.log('[HUG & KISS] pending_hugs table & index verified ✅');
}).catch((err) => {
  console.error('[HUG & KISS] DB migration error:', err.message);
});

// ── Express REST Router ─────────────────────────────────────────────────────
const router = express.Router();
router.use(authenticateToken);

let ioInstance = null;
function setIO(io) {
  ioInstance = io;
}

// Helper to fetch user name
async function getUserName(userId) {
  try {
    const res = await pool.query('SELECT name, username FROM users WHERE id = $1', [userId]);
    if (res.rows.length > 0) {
      return res.rows[0].name || res.rows[0].username || `User ${userId}`;
    }
  } catch (_) {}
  return userId === 1 ? 'User 1' : 'User 2';
}

// POST /hug-kiss/hug - Send Hug
router.post('/hug', async (req, res) => {
  try {
    const { conversationId } = req.body;
    const senderId = Number(req.user?.userId || req.user?.id);
    const convId = Number(conversationId || 1);

    if (!senderId) {
      return res.status(401).json({ success: false, message: 'Unauthorized' });
    }

    const recipientId = senderId === 1 ? 2 : 1;
    const senderName = await getUserName(senderId);

    // Check if recipient is online in userSockets or room
    const isOnline = ioInstance && ioInstance.sockets.adapter.rooms.has(`user_${recipientId}`);

    const dbRes = await pool.query(
      `INSERT INTO pending_hugs (conversation_id, sender_id, sender_name, recipient_id, is_delivered, delivered_at)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING *`,
      [convId, senderId, senderName, recipientId, isOnline ? true : false, isOnline ? new Date() : null]
    );

    const hug = dbRes.rows[0];

    if (ioInstance && isOnline) {
      ioInstance.to(`user_${recipientId}`).emit('hug_received', {
        id: hug.id,
        conversationId: convId,
        senderId,
        senderName,
        createdAt: hug.created_at,
        isLive: true,
      });
    }

    return res.status(201).json({
      success: true,
      hug,
      deliveredLive: Boolean(isOnline),
    });
  } catch (err) {
    console.error('[HUG & KISS] POST /hug error:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// GET /hug-kiss/pending - Retrieve undelivered hugs for current user
router.get('/pending', async (req, res) => {
  try {
    const userId = Number(req.user?.userId || req.user?.id);
    if (!userId) {
      return res.status(401).json({ success: false, message: 'Unauthorized' });
    }

    const { rows } = await pool.query(
      `SELECT * FROM pending_hugs 
       WHERE recipient_id = $1 AND is_delivered = false 
       ORDER BY created_at ASC`,
      [userId]
    );

    if (rows.length > 0) {
      await pool.query(
        `UPDATE pending_hugs 
         SET is_delivered = true, delivered_at = NOW() 
         WHERE recipient_id = $1 AND is_delivered = false`,
        [userId]
      );
    }

    return res.json({ success: true, pendingHugs: rows });
  } catch (err) {
    console.error('[HUG & KISS] GET /pending error:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ── In-Memory Kiss Matchmaker (Server Timestamp Authority) ──────────────────
// conversationId -> Map<userId, { touchStartServerTime: number, timeoutHandle: Timeout, successTimer: Timeout, isHolding: boolean }>
const activeKissSessions = new Map();

function getSessionMap(conversationId) {
  const key = String(conversationId);
  if (!activeKissSessions.has(key)) {
    activeKissSessions.set(key, new Map());
  }
  return activeKissSessions.get(key);
}

function clearUserKiss(conversationId, userId) {
  const session = getSessionMap(conversationId);
  const data = session.get(userId);
  if (data) {
    if (data.timeoutHandle) clearTimeout(data.timeoutHandle);
    if (data.successTimer) clearTimeout(data.successTimer);
    session.delete(userId);
  }
}

// ── Real-Time Socket Event Handlers ─────────────────────────────────────────
function registerHugKissHandlers(io, socket, userSockets) {
  setIO(io);

  const getUserId = (data) => {
    const raw = data?.senderId || data?.userId || socket.user?.userId || socket.user?.id || socket.data?.userId;
    return Number(raw) || 1;
  };

  // ── Hug Real-Time Event ───────────────────────────────────────────────────
  socket.on('hug_send', async (data) => {
    try {
      const userId = getUserId(data);
      const partnerId = userId === 1 ? 2 : 1;
      const convId = Number(data?.conversationId || 1);
      const senderName = await getUserName(userId);
      const isOnline = userSockets && userSockets.has(partnerId) && userSockets.get(partnerId).size > 0;

      const dbRes = await pool.query(
        `INSERT INTO pending_hugs (conversation_id, sender_id, sender_name, recipient_id, is_delivered, delivered_at)
         VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING *`,
        [convId, userId, senderName, partnerId, isOnline ? true : false, isOnline ? new Date() : null]
      );

      const hug = dbRes.rows[0];

      if (isOnline) {
        io.to(`user_${partnerId}`).emit('hug_received', {
          id: hug.id,
          conversationId: convId,
          senderId: userId,
          senderName,
          createdAt: hug.created_at,
          isLive: true,
        });
        console.log(`[HUG & KISS] Live Hug sent from User ${userId} -> User ${partnerId} 🫂✨`);
      } else {
        console.log(`[HUG & KISS] User ${partnerId} is offline. Hug stored in DB for next login 📬`);
      }

      socket.emit('hug_sent_ack', {
        success: true,
        hugId: hug.id,
        deliveredLive: isOnline,
      });
    } catch (err) {
      console.error('[HUG & KISS] hug_send error:', err.message);
      socket.emit('hug_sent_ack', { success: false, error: err.message });
    }
  });

  // ── Kiss Sync Matchmaker Events ───────────────────────────────────────────
  socket.on('kiss_touch_down', (data) => {
    try {
      const userId = getUserId(data);
      const partnerId = userId === 1 ? 2 : 1;
      const convId = Number(data?.conversationId || 1);
      const serverTime = Date.now();
      const session = getSessionMap(convId);

      clearUserKiss(convId, userId);

      console.log(`[KISS SYNC] User ${userId} touch down at server time: ${serverTime} (conv: ${convId})`);

      const timeoutHandle = setTimeout(() => {
        clearUserKiss(convId, userId);
        socket.emit('kiss_timeout', {
          conversationId: convId,
          message: 'Partner did not kiss back in time.',
        });
        console.log(`[KISS SYNC] User ${userId} kiss attempt timed out after 10s.`);
      }, 10000);

      const userTouch = {
        touchStartServerTime: serverTime,
        timeoutHandle,
        successTimer: null,
        isHolding: true,
      };

      session.set(userId, userTouch);

      io.to(`user_${partnerId}`).emit('kiss_partner_status', {
        conversationId: convId,
        partnerId: userId,
        isPressing: true,
        serverTime,
      });

      const partnerTouch = session.get(partnerId);

      if (partnerTouch && partnerTouch.isHolding) {
        const timeDiff = Math.abs(serverTime - partnerTouch.touchStartServerTime);
        console.log(`[KISS SYNC] Both users touching! Server time diff: ${timeDiff}ms`);

        if (timeDiff <= 500) {
          console.log(`[KISS SYNC] Match window passed (<= 500ms)! Syncing hold duration...`);
          const elapsed = serverTime - partnerTouch.touchStartServerTime;
          const remainingHold = Math.max(1000, 1000 - elapsed);

          if (userTouch.timeoutHandle) clearTimeout(userTouch.timeoutHandle);
          if (partnerTouch.timeoutHandle) clearTimeout(partnerTouch.timeoutHandle);

          const syncStartPayload = {
            conversationId: convId,
            syncDiffMs: timeDiff,
            holdTargetMs: 1000,
          };
          io.to(`user_${userId}`).emit('kiss_sync_matched', syncStartPayload);
          io.to(`user_${partnerId}`).emit('kiss_sync_matched', syncStartPayload);

          const successTimer = setTimeout(() => {
            const uT = session.get(userId);
            const pT = session.get(partnerId);

            if (uT && uT.isHolding && pT && pT.isHolding) {
              const successPayload = {
                success: true,
                conversationId: convId,
                matchedAt: Date.now(),
                syncDiffMs: timeDiff,
              };

              console.log(`[KISS SYNC] 💋 KISS SUCCESS! Emitting to User ${userId} and User ${partnerId} simultaneously!`);
              io.to(`user_${userId}`).emit('kiss_success', successPayload);
              io.to(`user_${partnerId}`).emit('kiss_success', successPayload);

              clearUserKiss(convId, userId);
              clearUserKiss(convId, partnerId);
            }
          }, remainingHold);

          userTouch.successTimer = successTimer;
          partnerTouch.successTimer = successTimer;
        } else {
          console.log(`[KISS SYNC] Touch gap was ${timeDiff}ms (> 500ms limit).`);
          socket.emit('kiss_sync_window_missed', {
            conversationId: convId,
            timeDiffMs: timeDiff,
            message: 'Touches must be within 500ms of each other. Try touching together!',
          });
        }
      }
    } catch (err) {
      console.error('[KISS SYNC] kiss_touch_down error:', err.message);
    }
  });

  socket.on('kiss_touch_up', (data) => {
    try {
      const userId = getUserId(data);
      const partnerId = userId === 1 ? 2 : 1;
      const convId = Number(data?.conversationId || 1);
      const session = getSessionMap(convId);
      const userTouch = session.get(userId);

      if (userTouch) {
        if (userTouch.successTimer) {
          clearTimeout(userTouch.successTimer);
          const partnerTouch = session.get(partnerId);
          if (partnerTouch && partnerTouch.successTimer) {
            clearTimeout(partnerTouch.successTimer);
          }
          io.to(`user_${userId}`).emit('kiss_cancelled', { reason: 'Hold was released before 1 second.' });
          io.to(`user_${partnerId}`).emit('kiss_cancelled', { reason: 'Partner released before 1 second.' });
        }

        clearUserKiss(convId, userId);
      }

      io.to(`user_${partnerId}`).emit('kiss_partner_status', {
        conversationId: convId,
        partnerId: userId,
        isPressing: false,
      });

      console.log(`[KISS SYNC] User ${userId} released touch (conv: ${convId})`);
    } catch (err) {
      console.error('[KISS SYNC] kiss_touch_up error:', err.message);
    }
  });

  socket.on('disconnect', () => {
    try {
      const userId = getUserId();
      const partnerId = userId === 1 ? 2 : 1;
      activeKissSessions.forEach((session, convId) => {
        if (session.has(userId)) {
          clearUserKiss(convId, userId);
          io.to(`user_${partnerId}`).emit('kiss_partner_status', {
            conversationId: Number(convId),
            partnerId: userId,
            isPressing: false,
          });
        }
      });
    } catch (err) {
      console.error('[KISS SYNC] disconnect error:', err.message);
    }
  });
}

module.exports = {
  hugKissRouter: router,
  registerHugKissHandlers,
  setHugKissIO: setIO,
};
