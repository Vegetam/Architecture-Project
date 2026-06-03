const http = require('http');
const { spawn } = require('child_process');

const PORT = 3097;

function get(path) {
  return new Promise((resolve, reject) => {
    http.get(`http://localhost:${PORT}${path}`, (res) => {
      let body = '';
      res.on('data', d => body += d);
      res.on('end', () => resolve({ status: res.statusCode, body: res.headers['content-type']?.includes('json') ? JSON.parse(body) : body }));
    }).on('error', reject);
  });
}

function wait(ms) { return new Promise(r => setTimeout(r, ms)); }

async function run() {
  const proc = spawn('node', ['server.js'], {
    env: { ...process.env, PORT: String(PORT), SERVICE_NAME: 'order-service' }
  });
  proc.stderr.on('data', d => process.stderr.write(d));
  await wait(500);

  let passed = 0; let failed = 0;

  async function test(name, fn) {
    try { await fn(); console.log(`  PASS  ${name}`); passed++; }
    catch (e) { console.log(`  FAIL  ${name}: ${e.message}`); failed++; }
  }

  await test('GET /health/live returns 200', async () => {
    const r = await get('/health/live');
    if (r.status !== 200) throw new Error(`expected 200, got ${r.status}`);
    if (r.body.status !== 'live') throw new Error(`expected live, got ${r.body.status}`);
  });

  await test('GET /health/ready returns 200', async () => {
    const r = await get('/health/ready');
    if (r.status !== 200) throw new Error(`expected 200, got ${r.status}`);
    if (r.body.status !== 'ready') throw new Error(`expected ready, got ${r.body.status}`);
  });

  await test('GET /metrics returns 200', async () => {
    const r = await get('/metrics');
    if (r.status !== 200) throw new Error(`expected 200, got ${r.status}`);
  });

  console.log(`\n${passed} passed, ${failed} failed`);
  proc.kill('SIGTERM');
  process.exit(failed > 0 ? 1 : 0);
}

run().catch(e => { console.error(e); process.exit(1); });
