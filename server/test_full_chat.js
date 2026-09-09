require('dotenv').config();
const { io } = require('socket.io-client');

const targetUrl = process.argv[2] || 'http://localhost:5000';

const u1Email = process.env.DUO_USER1_EMAIL || 'pottoda65@gmail.com';
const u1Pass = process.env.DUO_USER1_PASSWORD || 'Pottoda@9492982325';

const u2Email = process.env.DUO_USER2_EMAIL || 'pottiamma45@gmail.com';
const u2Pass = process.env.DUO_USER2_PASSWORD || 'Pottiamma@9505954559';

async function runEndToEndTest() {
  console.log('🚀 Starting Full End-to-End Chat Test');
  console.log(`🌐 Target Server: ${targetUrl}`);

  // 1. LOGIN USER 1
  console.log(`\n🔑 1. Logging in User 1 (${u1Email})...`);
  const res1 = await fetch(`${targetUrl}/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: u1Email, password: u1Pass })
  });
  const data1 = await res1.json();
  if (!data1.success) throw new Error(`User 1 Login Failed: ${data1.message}`);
  console.log(`   ✅ User 1 Logged in! (ID: ${data1.user.id}, Token: ${data1.token.substring(0, 15)}...)`);
  const token1 = data1.token;

  // 2. LOGIN USER 2
  console.log(`\n🔑 2. Logging in User 2 (${u2Email})...`);
  const res2 = await fetch(`${targetUrl}/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: u2Email, password: u2Pass })
  });
  const data2 = await res2.json();
  if (!data2.success) throw new Error(`User 2 Login Failed: ${data2.message}`);
  console.log(`   ✅ User 2 Logged in! (ID: ${data2.user.id}, Token: ${data2.token.substring(0, 15)}...)`);
  const token2 = data2.token;

  // 3. FETCH CONVERSATION LIST FOR USER 1
  console.log(`\n💬 3. Fetching Conversations for User 1...`);
  const resConv = await fetch(`${targetUrl}/messages/conversations`, {
    headers: { 'Authorization': `Bearer ${token1}` }
  });
  const dataConv = await resConv.json();
  console.log(`   ✅ Conversations loaded! Total active: ${dataConv.conversations?.length || 0}`);

  // 4. CONNECT REAL-TIME SOCKET.IO
  console.log(`\n⚡ 4. Initializing Real-time Socket.IO Connections...`);

  const socket1 = io(targetUrl, {
    auth: { token: token1 },
    transports: ['websocket', 'polling']
  });

  const socket2 = io(targetUrl, {
    auth: { token: token2 },
    transports: ['websocket', 'polling']
  });

  await new Promise((resolve, reject) => {
    let connectedCount = 0;
    const onConn = () => {
      connectedCount++;
      if (connectedCount === 2) resolve();
    };
    socket1.on('connect', () => { console.log('   ✅ Socket 1 Connected (User 1)'); onConn(); });
    socket2.on('connect', () => { console.log('   ✅ Socket 2 Connected (User 2)'); onConn(); });
    socket1.on('connect_error', (err) => reject(new Error(`Socket 1 Connection Error: ${err.message}`)));
    socket2.on('connect_error', (err) => reject(new Error(`Socket 2 Connection Error: ${err.message}`)));
    setTimeout(() => reject(new Error('Socket connection timed out')), 10000);
  });

  // 5. JOIN USER ROOMS AND CONVERSATION ROOM
  console.log(`\n🚪 5. Joining User Rooms & Conversation Room 1...`);
  socket1.emit('joinUserRoom', { userId: 1 });
  socket2.emit('joinUserRoom', { userId: 2 });
  socket1.emit('joinConversation', { conversationId: 1 });
  socket2.emit('joinConversation', { conversationId: 1 });

  await new Promise(r => setTimeout(r, 500));

  // 6. REAL-TIME MESSAGE EXCHANGE (User 1 -> User 2)
  console.log(`\n📤 6. Sending Real-time Message: User 1 ➡️ User 2...`);
  const msg1Text = `Hello User 2! Live chat test at ${new Date().toLocaleTimeString()}`;

  const user2ReceivePromise = new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('User 2 timeout waiting for message')), 10000);
    socket2.on('newMessage', (msg) => {
      if (msg.sender_id === 1 && !msg.is_mine) {
        clearTimeout(timer);
        console.log(`   📩 User 2 received message in real-time! Content: "${msg.message}" (ID: ${msg.id})`);
        resolve(msg);
      }
    });
  });

  socket1.emit('sendMessage', {
    conversationId: 1,
    message: msg1Text,
    nonce: `nonce_u1_${Date.now()}`,
    isEncrypted: false
  });

  await user2ReceivePromise;

  // 7. REAL-TIME REPLY (User 2 -> User 1)
  console.log(`\n📤 7. Sending Real-time Reply: User 2 ➡️ User 1...`);
  const replyText = `Hello User 1! Reply received & confirmed at ${new Date().toLocaleTimeString()}`;

  const user1ReceivePromise = new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('User 1 timeout waiting for reply')), 10000);
    socket1.on('newMessage', (msg) => {
      if (msg.sender_id === 2 && !msg.is_mine) {
        clearTimeout(timer);
        console.log(`   📩 User 1 received reply in real-time! Content: "${msg.message}" (ID: ${msg.id})`);
        resolve(msg);
      }
    });
  });

  socket2.emit('sendMessage', {
    conversationId: 1,
    message: replyText,
    nonce: `nonce_u2_${Date.now()}`,
    isEncrypted: false
  });

  await user1ReceivePromise;

  // DISCONNECT SOCKETS
  socket1.disconnect();
  socket2.disconnect();

  console.log('\n=============================================================');
  console.log('App fully working — login, messaging, real-time chat anni test chesi confirm chesanu');
  console.log('=============================================================');
}

runEndToEndTest().catch(err => {
  console.error('\n❌ Test execution failed:', err.message);
  process.exit(1);
});
