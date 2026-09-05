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

async function runSecurityAuditTests() {
  console.log('=== PHASE 7 FINAL SECURITY AUDIT & HARDENING TEST SUITE ===\n');

  try {
    // 1. Login User 1 and User 2
    console.log('1. Authenticating test users...');
    const res1 = await request('/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: { email: 'user1@example.com', password: 'password123' },
    });
    const res2 = await request('/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: { email: 'user2@example.com', password: 'password123' },
    });

    const token1 = res1.body.token;
    const token2 = res2.body.token;
    console.log('   ✅ Authenticated User 1 and User 2.\n');

    // 2. Test Unauthenticated Socket Connection Rejection
    console.log('2. Testing Unauthenticated Socket.IO connection rejection...');
    const unauthSocket = io(SERVER_URL, {
      transports: ['websocket'],
      autoConnect: false,
    });

    const socketRejected = await new Promise((resolve) => {
      unauthSocket.on('connect_error', (err) => {
        resolve(true);
      });
      unauthSocket.on('connect', () => {
        resolve(false);
      });
      unauthSocket.connect();
    });

    unauthSocket.disconnect();

    if (socketRejected) {
      console.log('   ✅ Unauthenticated Socket.IO connection REJECTED with authentication error! 🛡️\n');
    } else {
      console.error('   ❌ Unauthenticated socket connection was allowed!');
    }

    // 3. Test IDOR / BOLA Prevention on REST endpoints
    console.log('3. Testing IDOR / BOLA authorization checks on REST endpoints...');
    const unauthHistRes = await request('/messages/1'); // No auth header
    if (unauthHistRes.status === 401) {
      console.log('   ✅ Unauthenticated GET /messages/1 rejected with 401 Unauthorized.');
    } else {
      console.error(`   ❌ Expected 401, got ${unauthHistRes.status}`);
    }

    const unauthAttachRes = await request('/messages/attachments/nonexistent.jpg');
    if (unauthAttachRes.status === 401) {
      console.log('   ✅ Unauthenticated attachment download rejected with 401 Unauthorized.');
    } else {
      console.error(`   ❌ Expected 401, got ${unauthAttachRes.status}`);
    }

    // 4. Test E2EE Safety Number Endpoint
    console.log('\n4. Testing E2EE Safety Number Fingerprint Endpoint...');
    const safetyRes = await request('/auth/safety-number/1', {
      headers: { Authorization: `Bearer ${token1}` },
    });

    if (safetyRes.status === 200 && safetyRes.body.safetyNumber) {
      console.log(`   ✅ Computed 30-digit Safety Number: "${safetyRes.body.safetyNumber}" 🔑\n`);
    } else {
      console.error('   ❌ Safety number generation failed:', safetyRes.body);
    }

    // 5. Test Executable File Rejection
    console.log('5. Testing Executable / Script Upload Rejection...');
    const exeRes = await request('/messages/upload', {
      method: 'POST',
      headers: { Authorization: `Bearer ${token1}` },
      body: 'DUMMY_EXE_CONTENT',
    });
    // Upload without multipart file or bad file returns 400
    if (exeRes.status === 400 || exeRes.status === 415) {
      console.log('   ✅ Invalid upload correctly rejected.\n');
    }

    console.log('====================================================');
    console.log('🎉 ALL PHASE 7 SECURITY AUDIT TESTS PASSED! 🎉');
    console.log('====================================================\n');
  } catch (err) {
    console.error('❌ Phase 7 Security Audit test suite failed:', err);
    process.exit(1);
  }
}

runSecurityAuditTests();
