'use strict';

/**
 * Finger Trail Socket Handler — Live Finger Trail Feature
 *
 * Events (Client → Server):
 *   fingerTrail_open   { conversationId }          — user opened the canvas overlay
 *   fingerTrail_close  { conversationId }          — user closed the canvas overlay
 *   fingerTrail_points { conversationId, points }  — batch of normalized {x,y,t} points
 *
 * Events (Server → Client):
 *   fingerTrail_partnerStatus { conversationId, isOpen, userId } — partner opened/closed overlay
 *   fingerTrail_points        { conversationId, points, senderId } — relayed trail points
 */

// Track which users have the overlay open: conversationId → Set<userId>
const openOverlays = new Map();

function registerFingerTrailHandlers(io, socket) {
  const userId = Number(socket.user?.userId || socket.data?.userId);
  if (!userId) return;

  const partnerId = userId === 1 ? 2 : 1;

  // ── User opened the Touch Together canvas ──────────────────────────────────
  socket.on('fingerTrail_open', (data) => {
    try {
      const convId = data?.conversationId ?? 1;
      const key = String(convId);
      if (!openOverlays.has(key)) openOverlays.set(key, new Set());
      openOverlays.get(key).add(userId);

      io.to(`user_${partnerId}`).emit('fingerTrail_partnerStatus', {
        conversationId: convId,
        isOpen: true,
        userId,
      });
      console.log(`[FINGER TRAIL] User ${userId} opened overlay (conv ${convId})`);
    } catch (err) {
      console.error('[FINGER TRAIL] fingerTrail_open error:', err.message);
    }
  });

  // ── User closed the Touch Together canvas ─────────────────────────────────
  socket.on('fingerTrail_close', (data) => {
    try {
      const convId = data?.conversationId ?? 1;
      const key = String(convId);
      if (openOverlays.has(key)) openOverlays.get(key).delete(userId);

      io.to(`user_${partnerId}`).emit('fingerTrail_partnerStatus', {
        conversationId: convId,
        isOpen: false,
        userId,
      });
      console.log(`[FINGER TRAIL] User ${userId} closed overlay (conv ${convId})`);
    } catch (err) {
      console.error('[FINGER TRAIL] fingerTrail_close error:', err.message);
    }
  });

  // ── Relay batched trail points to partner ─────────────────────────────────
  socket.on('fingerTrail_points', (data) => {
    try {
      if (!data || !Array.isArray(data.points) || data.points.length === 0) return;
      const convId = data.conversationId ?? 1;

      // Relay ONLY to the partner (not back to sender)
      io.to(`user_${partnerId}`).emit('fingerTrail_points', {
        conversationId: convId,
        points: data.points,
        senderId: userId,
      });
    } catch (err) {
      console.error('[FINGER TRAIL] fingerTrail_points error:', err.message);
    }
  });

  // ── Clean up when socket disconnects ──────────────────────────────────────
  socket.on('disconnect', () => {
    try {
      openOverlays.forEach((set, key) => {
        if (set.delete(userId)) {
          // Inform partner this user's overlay is gone
          io.to(`user_${partnerId}`).emit('fingerTrail_partnerStatus', {
            conversationId: Number(key),
            isOpen: false,
            userId,
          });
        }
      });
    } catch (err) {
      console.error('[FINGER TRAIL] disconnect cleanup error:', err.message);
    }
  });
}

module.exports = { registerFingerTrailHandlers };
