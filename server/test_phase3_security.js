const http = require('http');
const fs = require('fs');
const path = require('path');

// Helper to make HTTP requests
function request(options, body = null) {
  return new Promise((resolve, reject) => {
    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          resolve({ statusCode: res.statusCode, headers: res.headers, body: data ? JSON.parse(data) : null, rawBody: data });
        } catch (e) {
          resolve({ statusCode: res.statusCode, headers: res.headers, body: null, rawBody: data });
        }
      });
    });
    req.on('error', reject);
    if (body) req.write(body);
    req.end();
  });
}

async function runSecurityTests() {
  console.log("=== RUNNING PHASE 3 SECURITY AUTOMATED TESTS ===");

  // 1. Login User 1
  const user1Login = await request({
    hostname: 'localhost',
    port: 5000,
    path: '/auth/login',
    method: 'POST',
    headers: { 'Content-Type': 'application/json' }
  }, JSON.stringify({ email: 'user1@duochat.com', password: 'password123' }));

  console.log(`TEST: Login User 1 -> Status: ${user1Login.statusCode}`);
  const user1Token = user1Login.body?.token;
  if (!user1Token) {
    console.error("FAIL: User 1 login failed");
    process.exit(1);
  }

  // 2. Unauthenticated request to attachment endpoint
  const unauthReq = await request({
    hostname: 'localhost',
    port: 5000,
    path: '/messages/attachments/file/sample-test-uuid.jpg',
    method: 'GET'
  });
  console.log(`TEST 4 (Unauthenticated Request): Status = ${unauthReq.statusCode} (Expected: 401)`);
  if (unauthReq.statusCode === 401) {
    console.log("✅ TEST 4 PASSED");
  } else {
    console.error("❌ TEST 4 FAILED");
  }

  // 3. Test File Type Validation - Executable File (.exe)
  const boundary = '----WebKitFormBoundary7MA4YWxkTrZu0gW';
  let multipartBody = '';
  multipartBody += `--${boundary}\r\n`;
  multipartBody += `Content-Disposition: form-data; name="conversationId"\r\n\r\n1\r\n`;
  multipartBody += `--${boundary}\r\n`;
  multipartBody += `Content-Disposition: form-data; name="attachmentType"\r\n\r\nfile\r\n`;
  multipartBody += `--${boundary}\r\n`;
  multipartBody += `Content-Disposition: form-data; name="file"; filename="malicious_virus.exe"\r\n`;
  multipartBody += `Content-Type: application/x-msdownload\r\n\r\n`;
  multipartBody += `MZ...fake binary executable payload...\r\n`;
  multipartBody += `--${boundary}--\r\n`;

  const exeUploadRes = await request({
    hostname: 'localhost',
    port: 5000,
    path: '/messages/upload',
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${user1Token}`,
      'Content-Type': `multipart/form-data; boundary=${boundary}`
    }
  }, multipartBody);

  console.log(`TEST 7 (Executable Upload Rejection): Status = ${exeUploadRes.statusCode} (Expected: 415)`);
  if (exeUploadRes.statusCode === 415) {
    console.log("✅ TEST 7 PASSED (Rejected executable file)");
  } else {
    console.error("❌ TEST 7 FAILED", exeUploadRes.body);
  }

  // 4. Test Valid Image Upload
  let validImageBody = '';
  validImageBody += `--${boundary}\r\n`;
  validImageBody += `Content-Disposition: form-data; name="conversationId"\r\n\r\n1\r\n`;
  validImageBody += `--${boundary}\r\n`;
  validImageBody += `Content-Disposition: form-data; name="message"\r\n\r\nPrivate Image Test\r\n`;
  validImageBody += `--${boundary}\r\n`;
  validImageBody += `Content-Disposition: form-data; name="attachmentType"\r\n\r\nimage\r\n`;
  validImageBody += `--${boundary}\r\n`;
  validImageBody += `Content-Disposition: form-data; name="file"; filename="secure_photo.png"\r\n`;
  validImageBody += `Content-Type: image/png\r\n\r\n`;
  validImageBody += `\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\nIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01\x0d\x0a\x2d\xb4\x00\x00\x00\x00IEND\xaeB\`\x82\r\n`;
  validImageBody += `--${boundary}--\r\n`;

  const imgUploadRes = await request({
    hostname: 'localhost',
    port: 5000,
    path: '/messages/upload',
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${user1Token}`,
      'Content-Type': `multipart/form-data; boundary=${boundary}`
    }
  }, validImageBody);

  console.log(`TEST 1 (Upload Image): Status = ${imgUploadRes.statusCode}`);
  const uploadedUrl = imgUploadRes.body?.data?.attachment_url;
  console.log(`Uploaded Attachment URL: ${uploadedUrl}`);

  if (uploadedUrl && uploadedUrl.includes('/messages/attachments/file/')) {
    console.log("✅ TEST 1 Upload PASSED (Secure URL generated)");

    // 5. User 1 accesses the attachment using JWT Authorization header
    const fileFilename = uploadedUrl.split('/messages/attachments/file/')[1];
    const user1AccessRes = await request({
      hostname: 'localhost',
      port: 5000,
      path: `/messages/attachments/file/${fileFilename}`,
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${user1Token}`
      }
    });

    console.log(`TEST 1 (User 1 access attachment): Status = ${user1AccessRes.statusCode} (Expected: 200)`);
    if (user1AccessRes.statusCode === 200) {
      console.log("✅ TEST 1 Access PASSED");
    }

    // 5. User 2 (participant in conversation 1) accesses User 1's attachment
    const user2Login = await request({
      hostname: 'localhost',
      port: 5000,
      path: '/auth/login',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({ email: 'user2@duochat.com', password: 'password123' }));

    const user2Token = user2Login.body?.token;
    if (user2Token) {
      const user2AccessRes = await request({
        hostname: 'localhost',
        port: 5000,
        path: `/messages/attachments/file/${fileFilename}`,
        method: 'GET',
        headers: {
          'Authorization': `Bearer ${user2Token}`
        }
      });
      console.log(`TEST 2 (User 2 participant access): Status = ${user2AccessRes.statusCode} (Expected: 200)`);
      if (user2AccessRes.statusCode === 200) {
        console.log("✅ TEST 2 PASSED (Conversation member authorized)");
      } else {
        console.error("❌ TEST 2 FAILED");
      }
    }

    // 6. Test Path Traversal Protection
    const pathTraversalRes = await request({
      hostname: 'localhost',
      port: 5000,
      path: `/messages/attachments/file/../../package.json`,
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${user1Token}`
      }
    });
    console.log(`TEST 9 (Path Traversal Protection): Status = ${pathTraversalRes.statusCode} (Expected: 403 or 404 or safe path)`);
    if (pathTraversalRes.statusCode === 403 || pathTraversalRes.statusCode === 404) {
      console.log("✅ TEST 9 PASSED");
    }
  } else {
    console.error("❌ TEST 1 FAILED", imgUploadRes.body);
  }

  console.log("=== ALL SECURITY TESTS COMPLETED ===");
  process.exit(0);
}

runSecurityTests().catch(err => {
  console.error("Error running tests:", err);
  process.exit(1);
});
