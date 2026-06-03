const express = require('express');
const client  = require('prom-client');

const app = express();
app.use(express.json());

const registry = new client.Registry();
client.collectDefaultMetrics({ register: registry });

const SVC = 'payment-service';

const httpCount = new client.Counter({
  name: 'otel_http_server_duration_count',
  help: 'Total HTTP requests',
  labelNames: ['service_name', 'http_status_code', 'http_method', 'http_route'],
  registers: [registry],
});

const httpDuration = new client.Histogram({
  name: 'otel_http_server_duration',
  help: 'HTTP request duration in ms',
  labelNames: ['service_name', 'http_method', 'http_route', 'http_status_code'],
  buckets: [10, 25, 50, 100, 200, 300, 500, 1000, 2500],
  registers: [registry],
});

app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const ms    = Date.now() - start;
    const code  = String(res.statusCode);
    const route = req.route?.path || req.path;
    httpCount.inc({ service_name: SVC, http_status_code: code, http_method: req.method, http_route: route });
    httpDuration.observe({ service_name: SVC, http_method: req.method, http_route: route, http_status_code: code }, ms);
  });
  next();
});

app.get('/health', (_req, res) => res.json({ status: 'ok', service: SVC }));

app.post('/payments', (req, res) => {
  setTimeout(() => {
    res.status(200).json({
      id:       `pay-${Date.now()}`,
      status:   'processed',
      orderId:  req.body?.orderId || 'unknown',
      amount:   req.body?.amount  || 0,
    });
  }, 8 + Math.random() * 15);
});

app.get('/metrics', async (_req, res) => {
  res.set('Content-Type', registry.contentType);
  res.end(await registry.metrics());
});

function simulateTraffic() {
  setInterval(() => {
    const ms   = 8 + Math.random() * 20;
    const code = Math.random() < 0.997 ? '200' : '500';
    httpCount.inc({ service_name: SVC, http_status_code: code, http_method: 'POST', http_route: '/payments' });
    httpDuration.observe({ service_name: SVC, http_method: 'POST', http_route: '/payments', http_status_code: code }, ms);
  }, 100);
}

simulateTraffic();

const PORT = process.env.PORT || 3001;
app.listen(PORT, () => console.log(`[payment-service] listening on :${PORT}`));
