'use strict';

const express = require('express');
const pool = require('./db');
const { authenticateToken } = require('./middleware/authMiddleware');

// ── Database Initialization ────────────────────────────────────────────────
pool.query(`
  CREATE TABLE IF NOT EXISTS shared_stars (
    id SERIAL PRIMARY KEY,
    conversation_id INTEGER NOT NULL,
    star_index INTEGER NOT NULL,
    star_name VARCHAR(255) NOT NULL,
    named_by_user_id INTEGER NOT NULL,
    named_by_user_name VARCHAR(255),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_conversation_star UNIQUE (conversation_id, star_index)
  );
  CREATE INDEX IF NOT EXISTS idx_shared_stars_conv ON shared_stars(conversation_id);
`).then(() => {
  console.log('[SHARED SKY] shared_stars table & index verified ✅');
}).catch((err) => {
  console.error('[SHARED SKY] DB migration error:', err.message);
});

// ── Express REST Router ───────────────────────────────────────────────────
const router = express.Router();
router.use(authenticateToken);

let ioInstance = null;
function setIO(io) {
  ioInstance = io;
}

// GET all named stars for conversation
router.get('/:conversationId', async (req, res) => {
  try {
    const convId = parseInt(req.params.conversationId, 10);
    if (isNaN(convId)) {
      return res.status(400).json({ success: false, message: 'Invalid conversationId' });
    }

    const { rows } = await pool.query(
      `SELECT * FROM shared_stars WHERE conversation_id = $1 ORDER BY created_at ASC`,
      [convId]
    );

    return res.json({ success: true, stars: rows });
  } catch (err) {
    console.error('[SHARED SKY] GET stars error:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// POST name a new star
router.post('/', async (req, res) => {
  try {
    const { conversationId, starIndex, starName } = req.body;
    const userId = Number(req.user?.userId || req.user?.id);

    if (!conversationId || starIndex === undefined || !starName || !starName.trim()) {
      return res.status(400).json({ success: false, message: 'Missing required fields' });
    }

    // Fetch user name
    let userName = 'Someone';
    try {
      const uRes = await pool.query('SELECT name, username FROM users WHERE id = $1', [userId]);
      if (uRes.rows.length > 0) {
        userName = uRes.rows[0].name || uRes.rows[0].username || `User ${userId}`;
      }
    } catch (_) {}

    const trimmedName = starName.trim();
    const { rows } = await pool.query(
      `INSERT INTO shared_stars (conversation_id, star_index, star_name, named_by_user_id, named_by_user_name)
       VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT (conversation_id, star_index) DO NOTHING
       RETURNING *`,
      [conversationId, starIndex, trimmedName, userId, userName]
    );

    if (rows.length === 0) {
      return res.status(409).json({ success: false, message: 'This star has already been named!' });
    }

    const star = rows[0];

    // Emit real-time update to both users
    if (ioInstance) {
      const partnerId = userId === 1 ? 2 : 1;
      const payload = { conversationId, star };
      ioInstance.to(`user_${userId}`).emit('sharedSky_starNamed', payload);
      ioInstance.to(`user_${partnerId}`).emit('sharedSky_starNamed', payload);
    }

    return res.status(201).json({ success: true, star });
  } catch (err) {
    console.error('[SHARED SKY] POST name star error:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// PUT rename a star (owner only)
router.put('/:id', async (req, res) => {
  try {
    const starId = parseInt(req.params.id, 10);
    const { starName } = req.body;
    const userId = Number(req.user?.userId || req.user?.id);

    if (isNaN(starId) || !starName || !starName.trim()) {
      return res.status(400).json({ success: false, message: 'Invalid starId or starName' });
    }

    const trimmedName = starName.trim();
    const { rows } = await pool.query(
      `UPDATE shared_stars 
       SET star_name = $1, updated_at = CURRENT_TIMESTAMP 
       WHERE id = $2 AND named_by_user_id = $3 
       RETURNING *`,
      [trimmedName, starId, userId]
    );

    if (rows.length === 0) {
      return res.status(403).json({ success: false, message: 'You can only rename your own stars or star not found' });
    }

    const updatedStar = rows[0];
    const partnerId = userId === 1 ? 2 : 1;

    if (ioInstance) {
      const payload = { conversationId: updatedStar.conversation_id, star: updatedStar };
      ioInstance.to(`user_${userId}`).emit('sharedSky_starUpdated', payload);
      ioInstance.to(`user_${partnerId}`).emit('sharedSky_starUpdated', payload);
    }

    return res.json({ success: true, star: updatedStar });
  } catch (err) {
    console.error('[SHARED SKY] PUT rename star error:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// DELETE a star (owner only)
router.delete('/:id', async (req, res) => {
  try {
    const starId = parseInt(req.params.id, 10);
    const userId = Number(req.user?.userId || req.user?.id);

    if (isNaN(starId)) {
      return res.status(400).json({ success: false, message: 'Invalid starId' });
    }

    const { rows } = await pool.query(
      `DELETE FROM shared_stars 
       WHERE id = $1 AND named_by_user_id = $2 
       RETURNING *`,
      [starId, userId]
    );

    if (rows.length === 0) {
      return res.status(403).json({ success: false, message: 'You can only delete your own stars or star not found' });
    }

    const deletedStar = rows[0];
    const partnerId = userId === 1 ? 2 : 1;

    if (ioInstance) {
      const payload = {
        conversationId: deletedStar.conversation_id,
        starId: deletedStar.id,
        starIndex: deletedStar.star_index,
      };
      ioInstance.to(`user_${userId}`).emit('sharedSky_starDeleted', payload);
      ioInstance.to(`user_${partnerId}`).emit('sharedSky_starDeleted', payload);
    }

    return res.json({ success: true, starId });
  } catch (err) {
    console.error('[SHARED SKY] DELETE star error:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ── Socket Handler ────────────────────────────────────────────────────────
const openSkyViews = new Map(); // conversationId -> Set<userId>

function registerSharedSkyHandlers(io, socket) {
  setIO(io);

  const getUserId = (data) => {
    const raw = data?.userId || data?.senderId || socket.user?.userId || socket.user?.id || socket.data?.userId;
    return Number(raw) || 1;
  };

  // Partner opened Our Sky screen
  socket.on('sharedSky_open', (data) => {
    try {
      const userId = getUserId(data);
      const partnerId = userId === 1 ? 2 : 1;
      const convId = data?.conversationId ?? 1;
      const key = String(convId);
      if (!openSkyViews.has(key)) openSkyViews.set(key, new Set());
      openSkyViews.get(key).add(userId);

      io.to(`user_${partnerId}`).emit('sharedSky_partnerStatus', {
        conversationId: convId,
        isOpen: true,
        userId,
      });
      console.log(`[SHARED SKY] User ${userId} opened sky view (conv ${convId})`);
    } catch (err) {
      console.error('[SHARED SKY] sharedSky_open error:', err.message);
    }
  });

  // Partner closed Our Sky screen
  socket.on('sharedSky_close', (data) => {
    try {
      const userId = getUserId(data);
      const partnerId = userId === 1 ? 2 : 1;
      const convId = data?.conversationId ?? 1;
      const key = String(convId);
      if (openSkyViews.has(key)) openSkyViews.get(key).delete(userId);

      io.to(`user_${partnerId}`).emit('sharedSky_partnerStatus', {
        conversationId: convId,
        isOpen: false,
        userId,
      });
      console.log(`[SHARED SKY] User ${userId} closed sky view (conv ${convId})`);
    } catch (err) {
      console.error('[SHARED SKY] sharedSky_close error:', err.message);
    }
  });

  // Partner tap/hover on star (gives soft real-time glow to partner)
  socket.on('sharedSky_hover', (data) => {
    try {
      const userId = getUserId(data);
      const partnerId = userId === 1 ? 2 : 1;
      const convId = data?.conversationId ?? 1;
      const starIndex = data?.starIndex;
      const isHovering = data?.isHovering ?? true;

      io.to(`user_${partnerId}`).emit('sharedSky_partnerHover', {
        conversationId: convId,
        starIndex,
        isHovering,
        userId,
      });
    } catch (err) {
      console.error('[SHARED SKY] sharedSky_hover error:', err.message);
    }
  });

  // Clean up on disconnect
  socket.on('disconnect', () => {
    try {
      const userId = getUserId();
      const partnerId = userId === 1 ? 2 : 1;
      openSkyViews.forEach((set, key) => {
        if (set.delete(userId)) {
          io.to(`user_${partnerId}`).emit('sharedSky_partnerStatus', {
            conversationId: Number(key),
            isOpen: false,
            userId,
          });
        }
      });
    } catch (err) {
      console.error('[SHARED SKY] disconnect cleanup error:', err.message);
    }
  });
}

module.exports = {
  sharedSkyRouter: router,
  registerSharedSkyHandlers,
  setSharedSkyIO: setIO,
};
