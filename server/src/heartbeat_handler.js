// Heartbeat Share Socket Event Handler
// DuoChat - Realtime Heartbeat Sharing

function registerHeartbeatHandlers(io, socket, userSockets) {
  // Client starts sending heartbeat
  socket.on("heartbeat_start", (data) => {
    const currentUserId = socket.user?.userId || socket.data?.userId;
    const senderId = Number(currentUserId || data?.senderId || 1);
    const recipientId = senderId === 1 ? 2 : 1;
    const conversationId = data?.conversationId || 1;
    const bpm = data?.bpm || 75;

    console.log(`[HEARTBEAT] User ${senderId} started sharing heartbeat to User ${recipientId} (BPM: ${bpm})`);

    // Broadcast to recipient room AND conversation room
    io.to(`user_${recipientId}`).to(String(conversationId)).emit("heartbeat_start", {
      senderId,
      conversationId,
      bpm,
    });
  });

  // Client sends individual beat tick (lub/dub)
  socket.on("heartbeat_beat", (data) => {
    const currentUserId = socket.user?.userId || socket.data?.userId;
    const senderId = Number(currentUserId || data?.senderId || 1);
    const recipientId = senderId === 1 ? 2 : 1;
    const conversationId = data?.conversationId || 1;
    const beatType = data?.beatType || "lub"; // "lub" or "dub"

    io.to(`user_${recipientId}`).to(String(conversationId)).emit("heartbeat_beat", {
      senderId,
      conversationId,
      beatType,
    });
  });

  // Client stops sending heartbeat
  socket.on("heartbeat_stop", (data) => {
    const currentUserId = socket.user?.userId || socket.data?.userId;
    const senderId = Number(currentUserId || data?.senderId || 1);
    const recipientId = senderId === 1 ? 2 : 1;
    const conversationId = data?.conversationId || 1;

    console.log(`[HEARTBEAT] User ${senderId} stopped sharing heartbeat`);

    io.to(`user_${recipientId}`).to(String(conversationId)).emit("heartbeat_stop", {
      senderId,
      conversationId,
    });
  });
}

module.exports = { registerHeartbeatHandlers };
