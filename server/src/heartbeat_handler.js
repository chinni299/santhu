// Heartbeat Share Socket Event Handler
// DuoChat - Realtime Heartbeat Sharing

function registerHeartbeatHandlers(io, socket, userSockets) {
  const currentUserId = socket.user?.userId || socket.data?.userId;

  // Client starts sending heartbeat
  socket.on("heartbeat_start", (data) => {
    const senderId = Number(currentUserId || data?.senderId);
    const recipientId = senderId === 1 ? 2 : 1;
    const conversationId = data?.conversationId || 1;
    const bpm = data?.bpm || 75;

    // Check if recipient is online in userSockets
    const recipientSockets = userSockets.get(recipientId);
    const isRecipientOnline = recipientSockets && recipientSockets.size > 0;

    if (!isRecipientOnline) {
      console.log(`[HEARTBEAT] User ${senderId} tried sending heartbeat, but partner User ${recipientId} is OFFLINE.`);
      socket.emit("heartbeat_partner_offline", {
        conversationId,
        message: "Partner is offline",
      });
      return;
    }

    console.log(`[HEARTBEAT] User ${senderId} started sharing heartbeat to User ${recipientId} (BPM: ${bpm})`);
    
    // Forward heartbeat_start to partner's user room
    io.to(`user_${recipientId}`).emit("heartbeat_start", {
      senderId,
      conversationId,
      bpm,
    });
  });

  // Client sends individual beat tick (lub/dub)
  socket.on("heartbeat_beat", (data) => {
    const senderId = Number(currentUserId || data?.senderId);
    const recipientId = senderId === 1 ? 2 : 1;
    const conversationId = data?.conversationId || 1;
    const beatType = data?.beatType || "lub"; // "lub" or "dub"

    const recipientSockets = userSockets.get(recipientId);
    if (recipientSockets && recipientSockets.size > 0) {
      io.to(`user_${recipientId}`).emit("heartbeat_beat", {
        senderId,
        conversationId,
        beatType,
      });
    }
  });

  // Client stops sending heartbeat
  socket.on("heartbeat_stop", (data) => {
    const senderId = Number(currentUserId || data?.senderId);
    const recipientId = senderId === 1 ? 2 : 1;
    const conversationId = data?.conversationId || 1;

    console.log(`[HEARTBEAT] User ${senderId} stopped sharing heartbeat to User ${recipientId}`);

    io.to(`user_${recipientId}`).emit("heartbeat_stop", {
      senderId,
      conversationId,
    });
  });
}

module.exports = { registerHeartbeatHandlers };
