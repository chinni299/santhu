// Heartbeat Share Socket Event Handler
// DuoChat - Realtime Heartbeat Sharing

function registerHeartbeatHandlers(io, socket, userSockets) {
  const getUserId = (data) => {
    const raw = socket.user?.userId || socket.user?.id || socket.data?.userId || data?.senderId || data?.userId;
    return Number(raw) || 1;
  };

  // Client starts sending heartbeat
  socket.on("heartbeat_start", (data) => {
    const senderId = getUserId(data);
    const recipientId = senderId === 1 ? 2 : 1;
    const conversationId = data?.conversationId || 1;
    const bpm = data?.bpm || 75;

    console.log(`[HEARTBEAT] User ${senderId} started sharing heartbeat to User ${recipientId} (BPM: ${bpm})`);

    const payload = {
      senderId,
      conversationId: Number(conversationId),
      bpm,
    };

    io.to(`user_${recipientId}`).emit("heartbeat_start", payload);
    socket.to(String(conversationId)).emit("heartbeat_start", payload);
  });

  // Client sends individual beat tick (lub/dub)
  socket.on("heartbeat_beat", (data) => {
    const senderId = getUserId(data);
    const recipientId = senderId === 1 ? 2 : 1;
    const conversationId = data?.conversationId || 1;
    const beatType = data?.beatType || "lub";

    const payload = {
      senderId,
      conversationId: Number(conversationId),
      beatType,
    };

    io.to(`user_${recipientId}`).emit("heartbeat_beat", payload);
    socket.to(String(conversationId)).emit("heartbeat_beat", payload);
  });

  // Client stops sending heartbeat
  socket.on("heartbeat_stop", (data) => {
    const senderId = getUserId(data);
    const recipientId = senderId === 1 ? 2 : 1;
    const conversationId = data?.conversationId || 1;

    console.log(`[HEARTBEAT] User ${senderId} stopped sharing heartbeat`);

    const payload = {
      senderId,
      conversationId: Number(conversationId),
    };

    io.to(`user_${recipientId}`).emit("heartbeat_stop", payload);
    socket.to(String(conversationId)).emit("heartbeat_stop", payload);
  });
}

module.exports = { registerHeartbeatHandlers };
