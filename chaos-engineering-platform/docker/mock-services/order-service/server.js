const express = require('express');
const client  = require('prom-client');

const app = express();
app.use(express.json());

// ── Prometheus metrics matching the steady-state queries ──────────────────────
const registry = new client.Registry();
client.collectDefaultMetrics({ register: registry });

// Matches: otel_http_server_duration_count{service_name="order-service", http_status_code}
const httpCount = new client.Counter({
  name: 'otel_http_server_duration_count',
  help: 'Total HTTP requests',
  labelNames: ['service_name', 'http_status_code', 'http_method', 'http_route'],
  registers: [registry],
});

// Matches: otel_http_server_duration_bucket{service_name="order-service"}
const httpDuration = new client.Histogram({
  name: 'otel_http_server_duration',
  help: 'HTTP request duration in ms',
  labelNames: ['service_name', 'http_method', 'http_route', 'http_status_code'],
  buckets: [10, 25, 50, 100, 200, 300, 500, 1000, 2500],
  registers: [registry],
});

const SVC = 'order-service';

// ── Middleware: record every request ─────────────────────────────────────────
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const ms     = Date.now() - start;
    const code   = String(res.statusCode);
    const route  = req.route?.path || req.path;
    httpCount.inc({ service_name: SVC, http_status_code: code, http_method: req.method, http_route: route });
    httpDuration.observe({ service_name: SVC, http_method: req.method, http_route: route, http_status_code: code }, ms);
  });
  next();
});

// ── Routes ────────────────────────────────────────────────────────────────────
app.get('/health', (_req, res) => res.json({ status: 'ok', service: SVC }));

let orderSeq = 1;
app.post('/orders', (req, res) => {
  // Simulate ~5ms processing time
  setTimeout(() => {
    res.status(201).json({
      id:     `order-${orderSeq++}`,
      status: 'created',
      item:   req.body?.item || 'unknown',
    });
  }, 5 + Math.random() * 10);
});

app.get('/orders', (_req, res) => {
  res.json({ orders: orderSeq - 1, service: SVC });
});

// ── Prometheus scrape endpoint ────────────────────────────────────────────────
app.get('/metrics', async (_req, res) => {
  res.set('Content-Type', registry.contentType);
  res.end(await registry.metrics());
});

// ── Background traffic simulator (generates steady baseline metrics) ──────────
function simulateTraffic() {
  // ~10 req/s baseline
  setInterval(() => {
    const ms   = 5 + Math.random() * 30;
    const code = Math.random() < 0.995 ? '200' : '500'; // 99.5% success
    httpCount.inc({ service_name: SVC, http_status_code: code, http_method: 'POST', http_route: '/orders' });
    httpDuration.observe({ service_name: SVC, http_method: 'POST', http_route: '/orders', http_status_code: code }, ms);
  }, 100);
}

simulateTraffic();

const PORT = process.env.PORT || 3000;
const server = app.listen(PORT, () => console.log(`[order-service] listening on :${PORT}`));

const shutdown = (signal) => {
  console.log(`[order-service] ${signal} — shutting down`);
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(1), 10000);
};
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT',  () => shutdown('SIGINT'));
