'use strict';

/**
 * Finger Trail Socket Handler — Live Finger Trail Feature (Touch Together)
 *
 * Events (Client → Server):
 *   fingerTrail_open   { conversationId, userId }           — user opened the canvas overlay
 *   fingerTrail_close  { conversationId, userId }           — user closed the canvas overlay
 *   fingerTrail_points { conversationId, points, senderId } — batch of normalized {x,y,t} points
 *
 * Events (Server → Client):
 *   fingerTrail_partnerStatus { conversationId, isOpen, userId } — partner opened/closed overlay
 *   fingerTrail_points        { conversationId, points, senderId } — relayed trail points
 */

const openOverlays = new Map(); // conversationId -> Set<userId>

function registerFingerTrailHandlers(io, socket) {
  const getUserId = (data) => {
    const raw = data?.userId || data?.senderId || socket.user?.userId || socket.user?.id || socket.data?.userId;
    return Number(raw) || 0;
  };

  // ── User opened the Touch Together canvas ──────────────────────────────────
  socket.on('fingerTrail_open', (data) => {
    try {
      const userId = getUserId(data) || 1;
      const partnerId = userId === 1 ? 2 : 1;
      const convId = data?.conversationId ?? 1;
      const key = String(convId);

      if (!openOverlays.has(key)) openOverlays.set(key, new Set());
      openOverlays.get(key).add(userId);

      const isPartnerAlreadyOpen = openOverlays.get(key).has(partnerId);

      // 1. Tell THIS user whether their partner is already here
      socket.emit('fingerTrail_partnerStatus', {
        conversationId: convId,
        isOpen: isPartnerAlreadyOpen,
        userId: partnerId,
      });

      // 2. Tell the partner that this user has opened the overlay (triggers auto-sync)
      const partnerPayload = {
        conversationId: convId,
        isOpen: true,
        userId: userId,
      };

      io.to(`user_${partnerId}`).emit('fingerTrail_partnerStatus', partnerPayload);
      socket.to(String(convId)).emit('fingerTrail_partnerStatus', partnerPayload);
      console.log(`[FINGER TRAIL] User ${userId} opened overlay (conv ${convId}), partner ${partnerId} isAlreadyOpen=${isPartnerAlreadyOpen}`);
    } catch (err) {
      console.error('[FINGER TRAIL] fingerTrail_open error:', err.message);
    }
  });

  // ── User closed the Touch Together canvas ─────────────────────────────────
  socket.on('fingerTrail_close', (data) => {
    try {
      const userId = getUserId(data) || 1;
      const partnerId = userId === 1 ? 2 : 1;
      const convId = data?.conversationId ?? 1;
      const key = String(convId);

      if (openOverlays.has(key)) openOverlays.get(key).delete(userId);

      const payload = {
        conversationId: convId,
        isOpen: false,
        userId,
      };

      io.to(`user_${partnerId}`).emit('fingerTrail_partnerStatus', payload);
      socket.to(String(convId)).emit('fingerTrail_partnerStatus', payload);
      console.log(`[FINGER TRAIL] User ${userId} closed overlay (conv ${convId})`);
    } catch (err) {
      console.error('[FINGER TRAIL] fingerTrail_close error:', err.message);
    }
  });

  // ── Relay batched trail points to partner ─────────────────────────────────
  socket.on('fingerTrail_points', (data) => {
    try {
      if (!data || !Array.isArray(data.points) || data.points.length === 0) return;
      const userId = getUserId(data) || 1;
      const partnerId = userId === 1 ? 2 : 1;
      const convId = data.conversationId ?? 1;

      const payload = {
        conversationId: convId,
        points: data.points,
        senderId: userId,
      };

      // Relay to partner user room AND conversation room
      io.to(`user_${partnerId}`).emit('fingerTrail_points', payload);
      socket.to(String(convId)).emit('fingerTrail_points', payload);
    } catch (err) {
      console.error('[FINGER TRAIL] fingerTrail_points error:', err.message);
    }
  });

  // ── Clean up when socket disconnects ──────────────────────────────────────
  socket.on('disconnect', () => {
    try {
      const userId = getUserId();
      if (!userId) return;
      const partnerId = userId === 1 ? 2 : 1;

      openOverlays.forEach((set, key) => {
        if (set.delete(userId)) {
          const payload = {
            conversationId: Number(key),
            isOpen: false,
            userId,
          };
          io.to(`user_${partnerId}`).emit('fingerTrail_partnerStatus', payload);
          socket.to(key).emit('fingerTrail_partnerStatus', payload);
        }
      });
    } catch (err) {
      console.error('[FINGER TRAIL] disconnect cleanup error:', err.message);
    }
  });
}

module.exports = { registerFingerTrailHandlers };
