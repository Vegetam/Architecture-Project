const http = require('http');
const { spawn } = require('child_process');

const PORT = 3098;

function request(path) {
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
  const proc = spawn('node', ['server.js'], { env: { ...process.env, PORT: String(PORT) } });
  proc.stderr.on('data', d => process.stderr.write(d));
  await wait(500);

  let passed = 0;
  let failed = 0;

  async function test(name, fn) {
    try {
      await fn();
      console.log(`  PASS  ${name}`);
      passed++;
    } catch (e) {
      console.log(`  FAIL  ${name}: ${e.message}`);
      failed++;
    }
  }

  await test('GET /health returns 200', async () => {
    const r = await request('/health');
    if (r.status !== 200) throw new Error(`expected 200, got ${r.status}`);
    if (r.body.status !== 'ok') throw new Error(`expected status ok, got ${r.body.status}`);
  });

  await test('POST /payments returns 200', async () => {
    const res = await new Promise((resolve, reject) => {
      const body = JSON.stringify({ orderId: 'order-1', amount: 100 });
      const req = http.request({ hostname: 'localhost', port: PORT, path: '/payments', method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) }
      }, (res) => {
        let data = '';
        res.on('data', d => data += d);
        res.on('end', () => resolve({ status: res.statusCode, body: JSON.parse(data) }));
      });
      req.on('error', reject);
      req.write(body);
      req.end();
    });
    if (res.status !== 200) throw new Error(`expected 200, got ${res.status}`);
    if (!res.body.id) throw new Error('missing payment id in response');
  });

  await test('GET /metrics returns Prometheus text', async () => {
    const r = await request('/metrics');
    if (r.status !== 200) throw new Error(`expected 200, got ${r.status}`);
  });

  console.log(`\n${passed} passed, ${failed} failed`);
  proc.kill('SIGTERM');
  process.exit(failed > 0 ? 1 : 0);
}

run().catch(e => { console.error(e); process.exit(1); });
