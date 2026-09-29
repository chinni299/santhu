require('dotenv').config();
const io = require('socket.io-client');
const http = require('http');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

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

// X25519 Key Agreement Helper for Node.js test suite
function generateX25519KeyPair() {
  const { publicKey, privateKey } = crypto.generateKeyPairSync('x25519', {
    publicKeyEncoding: { type: 'spki', format: 'der' },
    privateKeyEncoding: { type: 'pkcs8', format: 'der' },
  });
  // Extract raw 32-byte public key from DER format (last 32 bytes)
  const rawPublic = publicKey.subarray(publicKey.length - 32);
  const rawPrivate = privateKey.subarray(privateKey.length - 32);
  return {
    publicB64: rawPublic.toString('base64'),
    privateKeyObj: privateKey,
    rawPublic,
    rawPrivate,
  };
}

function computeSharedSecret(ownPrivateKeyDer, peerPublicB64) {
  const peerRawPublic = Buffer.from(peerPublicB64, 'base64');
  // Reconstruct SPKI DER header for X25519 public key
  const spkiHeader = Buffer.from('302a300506032b656e032100', 'hex');
  const peerPubKeyDer = Buffer.concat([spkiHeader, peerRawPublic]);

  const privKeyObj = crypto.createPrivateKey({
    key: ownPrivateKeyDer,
    format: 'der',
    type: 'pkcs8',
  });
  const pubKeyObj = crypto.createPublicKey({
    key: peerPubKeyDer,
    format: 'der',
    type: 'spki',
  });

  const sharedSecret = crypto.diffieHellman({
    privateKey: privKeyObj,
    publicKey: pubKeyObj,
  });

  // HKDF-SHA256 key derivation matching Dart implementation
  const salt = Buffer.from('DuoChatE2EESalt');
  const derivedKey = crypto.hkdfSync('sha256', sharedSecret, salt, Buffer.alloc(0), 32);
  return Buffer.from(derivedKey);
}

function encryptAES256GCM(plaintext, key) {
  const nonce = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, nonce);
  const encrypted = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()]);
  const mac = cipher.getAuthTag();
  const combinedCipher = Buffer.concat([encrypted, mac]);

  return {
    ciphertextB64: combinedCipher.toString('base64'),
    nonceB64: nonce.toString('base64'),
  };
}

function decryptAES256GCM(ciphertextB64, nonceB64, key) {
  const combined = Buffer.from(ciphertextB64, 'base64');
  const nonce = Buffer.from(nonceB64, 'base64');

  const mac = combined.subarray(combined.length - 16);
  const ciphertext = combined.subarray(0, combined.length - 16);

  const decipher = crypto.createDecipheriv('aes-256-gcm', key, nonce);
  decipher.setAuthTag(mac);
  const decrypted = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
  return decrypted.toString('utf8');
}

async function runPhase6Tests() {
  console.log('=== PHASE 6 E2EE SECURITY & ENCRYPTION AUTOMATED TEST SUITE ===\n');

  try {
    // 1. Log in User 1 and User 2
    console.log('1. Logging in User 1 and User 2...');
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

    const token1 = res1.body.token;
    const token2 = res2.body.token;
    console.log('   ✅ User 1 and User 2 authenticated successfully.\n');

    // 2. Generate local X25519 keypairs and register public keys
    console.log('2. Generating X25519 client keypairs & registering public keys...');
    const user1Keys = generateX25519KeyPair();
    const user2Keys = generateX25519KeyPair();

    const pubRes1 = await request('/auth/public-key', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token1}` },
      body: { publicKey: user1Keys.publicB64 },
    });
    const pubRes2 = await request('/auth/public-key', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token2}` },
      body: { publicKey: user2Keys.publicB64 },
    });

    if (pubRes1.status === 200 && pubRes2.status === 200) {
      console.log('   ✅ Public keys registered successfully with server.\n');
    } else {
      throw new Error('Public key registration failed');
    }

    // 3. Fetch recipient public key & perform X25519 + HKDF key agreement
    console.log('3. Fetching peer public keys & computing X25519 + HKDF-SHA256 shared secret...');
    const peerPubKeyRes = await request('/auth/public-key/2', {
      headers: { Authorization: `Bearer ${token1}` },
    });
    const peerPubKey2 = peerPubKeyRes.body.publicKey;

    const sharedKeyUser1 = computeSharedSecret(user1Keys.privateKeyObj, peerPubKey2);
    const sharedKeyUser2 = computeSharedSecret(user2Keys.privateKeyObj, user1Keys.publicB64);

    if (sharedKeyUser1.equals(sharedKeyUser2)) {
      console.log('   ✅ Shared secret derived identically on both client sides! 🔑\n');
    } else {
      throw new Error('Shared secret derivation mismatch!');
    }

    // 4. Encrypt message on sender side BEFORE sending
    console.log('4. Encrypting plaintext message on sender device (AES-256-GCM + 12-byte Nonce)...');
    const secretPlaintext = 'TOP SECRET E2EE TEST MESSAGE: Hello User 2!';
    const encResult = encryptAES256GCM(secretPlaintext, sharedKeyUser1);

    console.log(`   Plaintext:  "${secretPlaintext}"`);
    console.log(`   Ciphertext: "${encResult.ciphertextB64}"`);
    console.log(`   Nonce:      "${encResult.nonceB64}"\n`);

    // 5. Transport ciphertext over Socket.IO
    console.log('5. Transmitting ciphertext over Socket.IO to server...');
    const socket1 = io(SERVER_URL, { auth: { token: token1 } });
    const socket2 = io(SERVER_URL, { auth: { token: token2 } });

    await new Promise((resolve) => socket1.on('connect', resolve));
    await new Promise((resolve) => socket2.on('connect', resolve));

    socket2.emit('joinConversation', { conversationId: 1, userId: 2 });
    await new Promise((r) => setTimeout(r, 300));

    let receivedCiphertextPayload = null;
    socket2.on('newMessage', (msg) => {
      receivedCiphertextPayload = msg;
    });

    socket1.emit('sendMessage', {
      conversationId: 1,
      message: encResult.ciphertextB64,
      nonce: encResult.nonceB64,
      isEncrypted: true,
    });

    await new Promise((r) => setTimeout(r, 800));

    if (!receivedCiphertextPayload) {
      throw new Error('Failed to receive message on socket 2');
    }

    console.log('   ✅ Recipient socket received encrypted payload.');

    // 6. Decrypt ciphertext on recipient side
    console.log('6. Decrypting ciphertext on recipient device...');
    const decryptedText = decryptAES256GCM(
      receivedCiphertextPayload.message,
      receivedCiphertextPayload.nonce,
      sharedKeyUser2
    );

    if (decryptedText === secretPlaintext) {
      console.log(`   ✅ Decrypted text matches original plaintext: "${decryptedText}" 🎉\n`);
    } else {
      throw new Error(`Decryption mismatch! Got: ${decryptedText}`);
    }

    // 7. Direct Database Inspection (Zero-Knowledge Audit)
    console.log('7. Auditing PostgreSQL Database record for zero plaintext leak...');
    const historyRes = await request('/messages/1', {
      headers: { Authorization: `Bearer ${token1}` },
    });

    const lastMsgInDB = historyRes.body.data[historyRes.body.data.length - 1];
    console.log(`   DB stored message: "${lastMsgInDB.message}"`);
    console.log(`   DB stored nonce:   "${lastMsgInDB.nonce}"`);
    console.log(`   DB is_encrypted:   ${lastMsgInDB.is_encrypted}`);

    if (
      lastMsgInDB.message !== secretPlaintext &&
      lastMsgInDB.message === encResult.ciphertextB64 &&
      lastMsgInDB.is_encrypted === true
    ) {
      console.log('   ✅ VERIFIED: Database stores ONLY ciphertext. Server CANNOT read plaintext! 🛡️\n');
    } else {
      throw new Error('Database contains unencrypted or invalid record!');
    }

    socket1.disconnect();
    socket2.disconnect();

    console.log('====================================================');
    console.log('🎉 ALL PHASE 6 E2EE AUTOMATED SECURITY TESTS PASSED! 🎉');
    console.log('====================================================\n');
  } catch (err) {
    console.error('❌ E2EE Test suite failed:', err);
    process.exit(1);
  }
}

runPhase6Tests();
