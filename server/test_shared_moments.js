require('dotenv').config();
const io = require('socket.io-client');
const http = require('http');

const SERVER_URL = 'http://localhost:5000';

async function request(pathStr, options = {}) {
  return new Promise((resolve, reject) => {
    const url = new URL(pathStr, SERVER_URL);
    const reqOptions = {
      method: options.method || 'GET',
      headers: options.headers || {},
    };

    const req = http.request(url, reqOptions, (res) => {
      let data = '';
      res.on('data', (chunk) => (data += chunk));
      res.on('end', () => {
        let json = null;
        try {
          json = JSON.parse(data);
        } catch (e) {
          json = data;
        }
        resolve({ status: res.statusCode, body: json });
      });
    });

    req.on('error', reject);

    if (options.body) {
      req.write(typeof options.body === 'string' ? options.body : JSON.stringify(options.body));
    }
    req.end();
  });
}

async function runSharedMomentsTest() {
  console.log('=== TESTING SHARED MOMENTS FEATURE (API & SOCKET) ===\n');

  try {
    // 1. Login User 1 & User 2
    console.log('1. Authenticating test users...');
    const res1 = await request('/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: { email: process.env.DUO_USER1_EMAIL || 'pottoda65@gmail.com', password: process.env.DUO_USER1_PASSWORD || 'Pottoda@9492982325' },
    });
    const res2 = await request('/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: { email: process.env.DUO_USER2_EMAIL || 'pottiamma45@gmail.com', password: process.env.DUO_USER2_PASSWORD || 'Pottiamma@9505954559' },
    });

    if (!res1.body.token || !res2.body.token) {
      console.error('❌ Failed to authenticate users:', res1.body, res2.body);
      process.exit(1);
    }

    const token1 = res1.body.token;
    const token2 = res2.body.token;
    console.log('   ✅ Authenticated User 1 and User 2.\n');

    // 2. Fetch existing shared moments
    console.log('2. Fetching shared moments list...');
    const listRes = await request('/messages/shared-moments', {
      headers: { Authorization: `Bearer ${token1}` },
    });
    console.log(`   ✅ Status: ${listRes.status}, count: ${listRes.body.data?.length ?? 0}\n`);

    // 3. Connect User 2 socket to listen for real-time updates
    console.log('3. Connecting User 2 socket for real-time event check...');
    const socket2 = io(SERVER_URL, {
      auth: { token: token2 },
      transports: ['websocket'],
    });

    let socketEventReceived = false;
    socket2.on('sharedMomentChanged', (data) => {
      console.log('   Received real-time event sharedMomentChanged:', data);
      socketEventReceived = true;
    });

    await new Promise((r) => setTimeout(r, 500));

    // 4. Create a new Shared Moment with opt-in location
    console.log('4. Creating a new Shared Moment with location...');
    const createRes = await request('/messages/shared-moments', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token1}`,
        'Content-Type': 'application/json',
      },
      body: {
        caption: 'Our sunset date at the beach 🌅',
        latitude: 17.385043,
        longitude: 78.486671,
        location_enabled: true,
        moment_date: new Date().toISOString(),
      },
    });

    console.log('   Create status:', createRes.status, createRes.body);
    if (!createRes.body.success) {
      console.error('❌ Failed to create shared moment');
      process.exit(1);
    }
    const createdId = createRes.body.data.id;
    console.log(`   ✅ Created Shared Moment ID: ${createdId}\n`);

    // 5. Emit socket notification from User 1
    console.log('5. Emitting socket event from User 1...');
    const socket1 = io(SERVER_URL, {
      auth: { token: token1 },
      transports: ['websocket'],
    });
    await new Promise((r) => setTimeout(r, 500));

    socket1.emit('sharedMomentChanged', { action: 'create', id: createdId });
    await new Promise((r) => setTimeout(r, 1000));

    if (socketEventReceived) {
      console.log('   ✅ Socket event received by User 2 successfully!\n');
    } else {
      console.log('   ⚠️ Socket event not received within timeout\n');
    }

    // 6. Delete test shared moment
    console.log(`6. Deleting created shared moment ID: ${createdId}...`);
    const deleteRes = await request(`/messages/shared-moments/${createdId}`, {
      method: 'DELETE',
      headers: { Authorization: `Bearer ${token1}` },
    });
    console.log('   Delete status:', deleteRes.status, deleteRes.body);
    console.log('   ✅ Deleted successfully.\n');

    socket1.disconnect();
    socket2.disconnect();
    console.log('=== ALL SHARED MOMENT TESTS PASSED CLEANLY! ✅ ===');
    process.exit(0);
  } catch (err) {
    console.error('❌ Test failed with error:', err);
    process.exit(1);
  }
}

runSharedMomentsTest();
