/**
 * Phase 6 Step 3 - Media + Audio E2EE Server-Side Test
 *
 * Verifies:
 *  1. Server accepts multipart upload with isEncrypted=true and nonce
 *  2. DB row has is_encrypted=true and nonce populated
 *  3. Server returns is_encrypted=true and nonce in response
 *  4. Attachment URL is accessible via authenticated GET
 *  5. Server rejects unauthenticated media fetch (auth enforcement)
 *  6. .bin file extension is accepted by multer allowlist
 */
require("dotenv").config();
const http = require("http");
const https = require("https");
const crypto = require("crypto");
const FormData = require("form-data");
const { URL } = require("url");

const SERVER_URL = process.env.TEST_SERVER_URL || "http://localhost:5000";
const USER1_EMAIL = process.env.DUO_USER1_EMAIL || "pottoda65@gmail.com";
const USER2_EMAIL = process.env.DUO_USER2_EMAIL || "pottiamma45@gmail.com";
const USER1_PASSWORD = process.env.DUO_USER1_PASSWORD || "Pottoda@9492982325";
const USER2_PASSWORD = process.env.DUO_USER2_PASSWORD || "Pottiamma@9505954559";
const CONVERSATION_ID = 1;

let passed = 0;
let failed = 0;

function pass(name) {
  console.log("  PASS  " + name);
  passed++;
}
function fail(name, reason) {
  console.log("  FAIL  " + name);
  console.log("          Reason: " + reason);
  failed++;
}

async function request(pathStr, options) {
  options = options || {};
  return new Promise(function(resolve, reject) {
    var url = new URL(pathStr, SERVER_URL);
    var isHttps = url.protocol === "https:";
    var lib = isHttps ? https : http;
    var reqOptions = {
      hostname: url.hostname,
      port: url.port || (isHttps ? 443 : 80),
      path: url.pathname + url.search,
      method: options.method || "GET",
      headers: options.headers || {},
    };
    var req = lib.request(reqOptions, function(res) {
      var chunks = [];
      res.on("data", function(c) { chunks.push(c); });
      res.on("end", function() {
        var raw = Buffer.concat(chunks).toString("utf8");
        var json = null;
        try { json = JSON.parse(raw); } catch(_) { json = raw; }
        resolve({ status: res.statusCode, body: json, headers: res.headers });
      });
    });
    req.on("error", reject);
    if (options.rawBody) {
      req.write(options.rawBody);
    } else if (options.body) {
      req.write(typeof options.body === "string" ? options.body : JSON.stringify(options.body));
    }
    req.end();
  });
}

async function login(email, password) {
  var res = await request("/auth/login", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email: email, password: password }),
  });
  if (res.status !== 200 || !res.body || !res.body.token) {
    throw new Error("Login failed for " + email + ": " + JSON.stringify(res.body));
  }
  return res.body.token;
}

async function multipartUpload(token, fields, fileBuffer, fileName) {
  return new Promise(function(resolve, reject) {
    var form = new FormData();
    Object.keys(fields).forEach(function(k) { form.append(k, String(fields[k])); });
    form.append("file", fileBuffer, { filename: fileName, contentType: "application/octet-stream" });

    var url = new URL("/messages/upload", SERVER_URL);
    var isHttps = url.protocol === "https:";
    var lib = isHttps ? https : http;

    var headers = Object.assign({}, form.getHeaders(), {
      "Authorization": "Bearer " + token,
    });

    var reqOptions = {
      hostname: url.hostname,
      port: url.port || (isHttps ? 443 : 80),
      path: url.pathname,
      method: "POST",
      headers: headers,
    };

    var req = lib.request(reqOptions, function(res) {
      var chunks = [];
      res.on("data", function(c) { chunks.push(c); });
      res.on("end", function() {
        var raw = Buffer.concat(chunks).toString("utf8");
        var json = null;
        try { json = JSON.parse(raw); } catch(_) { json = raw; }
        resolve({ status: res.statusCode, body: json });
      });
    });
    req.on("error", reject);
    form.pipe(req);
  });
}

async function runTests() {
  console.log("");
  console.log("=== Phase 6 Step 3 - Media + Audio E2EE Test ===");
  console.log("");

  var user1Token, user2Token;

  console.log("[1] Auth");
  try {
    user1Token = await login(USER1_EMAIL, USER1_PASSWORD);
    user2Token = await login(USER2_EMAIL, USER2_PASSWORD);
    pass("User 1 & 2 login OK");
  } catch(e) {
    fail("Login", e.message);
    console.log("\nCannot continue - server may not be running.\n");
    return;
  }

  console.log("\n[2] Upload encrypted image attachment (.bin with nonce)");
  var fakeEncryptedBytes = crypto.randomBytes(1040);
  var fakeNonce = crypto.randomBytes(12).toString("base64");
  var uploadRes = await multipartUpload(user1Token, {
    conversationId: CONVERSATION_ID,
    senderId: 1,
    attachmentType: "image",
    isEncrypted: "true",
    nonce: fakeNonce,
    message: "",
  }, fakeEncryptedBytes, "photo_enc.bin");

  var uploadedAttachmentUrl = null;
  if (uploadRes.status === 201 && uploadRes.body && uploadRes.body.success) {
    pass("Server accepted encrypted .bin upload (201)");
    uploadedAttachmentUrl = uploadRes.body.data && uploadRes.body.data.attachment_url;
  } else {
    fail("Encrypted .bin upload", "Status " + uploadRes.status + ": " + JSON.stringify(uploadRes.body));
  }

  console.log("\n[3] Verify DB row has is_encrypted=true and nonce stored");
  if (uploadRes.body && uploadRes.body.data) {
    var d = uploadRes.body.data;
    if (d.is_encrypted === true) {
      pass("DB row: is_encrypted=true");
    } else {
      fail("DB row: is_encrypted", "Expected true, got " + d.is_encrypted);
    }
    if (d.nonce === fakeNonce) {
      pass("DB row: nonce matches sent nonce");
    } else {
      fail("DB row: nonce", 'Expected "' + fakeNonce + '", got "' + d.nonce + '"');
    }
    if (d.attachment_type === "image") {
      pass("DB row: attachment_type=image (original type preserved)");
    } else {
      fail("DB row: attachment_type", 'Expected "image", got "' + d.attachment_type + '"');
    }
  } else {
    fail("DB row fields", "No data in response");
  }

  console.log("\n[4] Verify attachment URL accessible with auth");
  if (uploadedAttachmentUrl) {
    var getRes = await request(uploadedAttachmentUrl, {
      headers: { "Authorization": "Bearer " + user1Token },
    });
    if (getRes.status === 200) {
      pass("Authenticated GET of attachment returns 200");
    } else {
      fail("Authenticated GET", "Status " + getRes.status);
    }

    console.log("\n[5] Verify attachment URL rejected without auth");
    var unauthRes = await request(uploadedAttachmentUrl, {});
    if (unauthRes.status === 401 || unauthRes.status === 403) {
      pass("Unauthenticated GET rejected with " + unauthRes.status);
    } else {
      fail("Unauthenticated GET", "Expected 401/403, got " + unauthRes.status);
    }
  } else {
    fail("Attachment URL fetch", "No attachment_url in upload response");
    fail("Unauthenticated GET", "Skipped (no URL)");
  }

  console.log("\n[6] Upload encrypted audio attachment (.bin with nonce)");
  var fakeAudioBytes = crypto.randomBytes(2064);
  var audioNonce = crypto.randomBytes(12).toString("base64");
  var audioUploadRes = await multipartUpload(user2Token, {
    conversationId: CONVERSATION_ID,
    senderId: 2,
    attachmentType: "audio",
    isEncrypted: "true",
    nonce: audioNonce,
    message: "",
  }, fakeAudioBytes, "voice_enc.bin");

  if (audioUploadRes.status === 201 && audioUploadRes.body && audioUploadRes.body.success) {
    var ad = audioUploadRes.body.data;
    if (ad.is_encrypted === true && ad.nonce === audioNonce) {
      pass("Encrypted audio upload OK (201, is_encrypted=true, nonce stored)");
    } else {
      fail("Encrypted audio DB fields", "is_encrypted=" + ad.is_encrypted + ", nonce match=" + (ad.nonce === audioNonce));
    }
  } else {
    fail("Encrypted audio upload", "Status " + audioUploadRes.status + ": " + JSON.stringify(audioUploadRes.body));
  }

  console.log("\n[7] .bin extension is allowed by server file filter");
  if (uploadRes.status === 201) {
    pass(".bin extension accepted (upload succeeded)");
  } else {
    fail(".bin extension", "Upload was rejected - check ALLOWED_EXTENSIONS in messages.js");
  }

  console.log("\n[8] Original attachmentType preserved even for .bin files");
  if (uploadRes.body && uploadRes.body.data && uploadRes.body.data.attachment_type === "image") {
    pass("attachment_type=image preserved even when file is .bin");
  } else {
    fail("attachment_type", "Got " + (uploadRes.body && uploadRes.body.data && uploadRes.body.data.attachment_type) + " instead of image");
  }

  console.log("\n===================================================");
  console.log("  Results: " + passed + " PASS / " + failed + " FAIL");
  console.log("===================================================");
  if (failed === 0) {
    console.log("\n  Phase 6 Step 3 (Media + Audio E2EE) - ALL TESTS PASSED\n");
  } else {
    console.log("\n  " + failed + " test(s) failed\n");
    process.exitCode = 1;
  }
}

runTests().catch(function(e) {
  console.error("Unexpected error:", e);
  process.exitCode = 1;
});
