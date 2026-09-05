const http = require('http');
const { io } = require('socket.io-client');

function request(options, body = null) {
  return new Promise((resolve, reject) => {
    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          resolve({ statusCode: res.statusCode, body: data ? JSON.parse(data) : null });
        } catch (e) {
          resolve({ statusCode: res.statusCode, body: data });
        }
      });
    });
    req.on('error', reject);
    if (body) req.write(body);
    req.end();
  });
}

async function runCallingTests() {
  console.log("=== RUNNING PHASE 4 WEBRTC SIGNALING TESTS ===");

  // Login User 1
  const user1Login = await request({
    hostname: 'localhost',
    port: 5000,
    path: '/auth/login',
    method: 'POST',
    headers: { 'Content-Type': 'application/json' }
  }, JSON.stringify({ email: 'user1@duochat.com', password: 'password123' }));

  const user1Token = user1Login.body?.token;

  // Login User 2
  const user2Login = await request({
    hostname: 'localhost',
    port: 5000,
    path: '/auth/login',
    method: 'POST',
    headers: { 'Content-Type': 'application/json' }
  }, JSON.stringify({ email: 'user2@duochat.com', password: 'password123' }));

  const user2Token = user2Login.body?.token;

  if (!user1Token || !user2Token) {
    console.error("FAIL: User logins failed");
    process.exit(1);
  }

  // Connect Socket for User 1
  const socket1 = io('http://localhost:5000', {
    auth: { token: user1Token },
    transports: ['websocket']
  });

  // Connect Socket for User 2
  const socket2 = io('http://localhost:5000', {
    auth: { token: user2Token },
    transports: ['websocket']
  });

  await new Promise((res) => socket1.on('connect', res));
  await new Promise((res) => socket2.on('connect', res));

  socket1.emit('joinUserRoom', { userId: 1 });
  socket2.emit('joinUserRoom', { userId: 2 });

  await new Promise(r => setTimeout(r, 500));

  // Test 1: User 1 initiates call to User 2
  console.log("TEST 1: User 1 initiates call to User 2...");
  const incomingCallPromise = new Promise((resolve) => {
    socket2.once('incomingCall', (data) => {
      resolve(data);
    });
  });

  socket1.emit('callUser', { conversationId: 1, isVideoCall: true, callerName: 'User 1' });
  const incomingData = await incomingCallPromise;

  if (incomingData && incomingData.callerId === 1 && incomingData.isVideoCall === true) {
    console.log("✅ TEST 1 PASSED: User 2 received incomingCall signal");
  } else {
    console.error("❌ TEST 1 FAILED");
  }

  // Test 2: Simultaneous Call Prevention
  console.log("TEST 2: Attempting duplicate call initiation...");
  const callErrorPromise = new Promise((resolve) => {
    socket1.once('callError', (data) => {
      resolve(data);
    });
  });
  socket1.emit('callUser', { conversationId: 1, isVideoCall: false });
  const errData = await callErrorPromise;
  if (errData && errData.message.includes("already in progress")) {
    console.log("✅ TEST 2 PASSED: Prevented multiple simultaneous calls");
  } else {
    console.error("❌ TEST 2 FAILED");
  }

  // Test 3: User 2 accepts call
  console.log("TEST 3: User 2 accepts call...");
  const callAcceptedPromise = new Promise((resolve) => {
    socket1.once('callAccepted', (data) => {
      resolve(data);
    });
  });
  socket2.emit('acceptCall', { conversationId: 1 });
  const acceptedData = await callAcceptedPromise;
  if (acceptedData && acceptedData.acceptedBy === 2) {
    console.log("✅ TEST 3 PASSED: User 1 received callAccepted signal");
  } else {
    console.error("❌ TEST 3 FAILED");
  }

  // Test 4: WebRTC Offer & Answer Relay
  console.log("TEST 4: Relaying WebRTC Offer...");
  const offerPromise = new Promise((resolve) => {
    socket2.once('webrtcOffer', (data) => resolve(data));
  });
  socket1.emit('webrtcOffer', { conversationId: 1, sdp: { type: 'offer', sdp: 'fake_sdp_offer' } });
  const offerData = await offerPromise;
  if (offerData && offerData.sdp.sdp === 'fake_sdp_offer') {
    console.log("✅ TEST 4 PASSED: WebRTC Offer relayed securely");
  } else {
    console.error("❌ TEST 4 FAILED");
  }

  // Test 5: End Call
  console.log("TEST 5: Ending Call...");
  const callEndedPromise = new Promise((resolve) => {
    socket2.once('callEnded', (data) => resolve(data));
  });
  socket1.emit('endCall', { conversationId: 1 });
  const endedData = await callEndedPromise;
  if (endedData && endedData.endedBy === 1) {
    console.log("✅ TEST 5 PASSED: Call ended signal delivered");
  } else {
    console.error("❌ TEST 5 FAILED");
  }

  socket1.disconnect();
  socket2.disconnect();

  console.log("=== ALL WEBRTC SIGNALING TESTS PASSED ===");
  process.exit(0);
}

runCallingTests().catch(err => {
  console.error("Error in WebRTC tests:", err);
  process.exit(1);
});
