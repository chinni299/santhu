require('dotenv').config();

const baseUrl = 'https://santhu-swuo.onrender.com';

async function testApi() {
  console.log('🧪 Testing Live Backend Endpoints:', baseUrl);

  // 1. Test Root
  try {
    const resRoot = await fetch(`${baseUrl}/`);
    console.log(`\n1. GET / -> Status: ${resRoot.status}`);
    const textRoot = await resRoot.text();
    console.log(`   Response: ${textRoot}`);
  } catch (err) {
    console.error('❌ GET / Error:', err.message);
  }

  // 2. Test DB Test
  try {
    const resDb = await fetch(`${baseUrl}/db-test`);
    console.log(`\n2. GET /db-test -> Status: ${resDb.status}`);
    const textDb = await resDb.text();
    console.log(`   Response: ${textDb}`);
  } catch (err) {
    console.error('❌ GET /db-test Error:', err.message);
  }

  // 3. Test Login User 1
  const u1Email = process.env.DUO_USER1_EMAIL || 'pottoda65@gmail.com';
  const u1Pass = process.env.DUO_USER1_PASSWORD || 'Pottoda@9492982325';
  let token1 = null;

  try {
    const resL1 = await fetch(`${baseUrl}/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: u1Email, password: u1Pass })
    });
    console.log(`\n3. POST /auth/login (User 1: ${u1Email}) -> Status: ${resL1.status}`);
    const jsonL1 = await resL1.json();
    console.log(`   Response:`, JSON.stringify(jsonL1));
    if (jsonL1.success) token1 = jsonL1.token;
  } catch (err) {
    console.error('❌ Login User 1 Error:', err.message);
  }

  // 4. Test Login User 2
  const u2Email = process.env.DUO_USER2_EMAIL || 'pottiamma45@gmail.com';
  const u2Pass = process.env.DUO_USER2_PASSWORD || 'Pottiamma@9505954559';
  let token2 = null;

  try {
    const resL2 = await fetch(`${baseUrl}/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: u2Email, password: u2Pass })
    });
    console.log(`\n4. POST /auth/login (User 2: ${u2Email}) -> Status: ${resL2.status}`);
    const jsonL2 = await resL2.json();
    console.log(`   Response:`, JSON.stringify(jsonL2));
    if (jsonL2.success) token2 = jsonL2.token;
  } catch (err) {
    console.error('❌ Login User 2 Error:', err.message);
  }

  return { token1, token2 };
}

testApi();
