const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const http = require('http');
const { spawn } = require('child_process');

const PORT = 3099;

function request(method, path, body) {
  return new Promise((resolve, reject) => {
    const payload = body ? JSON.stringify(body) : null;
    const opts = {
      hostname: 'localhost', port: PORT, path, method,
      headers: { 'Content-Type': 'application/json', ...(payload ? { 'Content-Length': Buffer.byteLength(payload) } : {}) }
    };
    const req = http.request(opts, (res) => {
      let data = '';
      res.on('data', d => data += d);
      res.on('end', () => {
        const isJson = res.headers['content-type']?.includes('json');
        resolve({ status: res.statusCode, body: isJson ? JSON.parse(data) : data });
      });
    });
    req.on('error', reject);
    if (payload) req.write(payload);
    req.end();
  });
}

let proc;

before(async () => {
  proc = spawn('node', ['server.js'], { cwd: __dirname, env: { ...process.env, PORT: String(PORT) } });
  await new Promise(r => setTimeout(r, 500));
});

after(() => { if (proc) proc.kill('SIGTERM'); });

test('GET /health returns 200 with status ok', async () => {
  const r = await request('GET', '/health');
  assert.equal(r.status, 200);
  assert.equal(r.body.status, 'ok');
  assert.equal(r.body.service, 'order-service');
});

test('POST /orders returns 201 with order id', async () => {
  const r = await request('POST', '/orders', { item: 'test-widget' });
  assert.equal(r.status, 201);
  assert.ok(r.body.id, 'response must include an order id');
  assert.equal(r.body.status, 'created');
});

test('GET /metrics returns Prometheus text format', async () => {
  const r = await request('GET', '/metrics');
  assert.equal(r.status, 200);
  assert.ok(r.body.includes('otel_http_server_duration_count'), 'metrics must include otel counter');
});
