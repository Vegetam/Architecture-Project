const express = require("express");
const client = require("prom-client");

const SERVICE_NAME = process.env.SERVICE_NAME || "payment-service";
const PORT = parseInt(process.env.PORT || "3002", 10);

const app = express();
app.use(express.json());

// Prometheus metrics
client.collectDefaultMetrics();
const httpReqs = new client.Counter({
  name: "http_requests_total",
  help: "Total HTTP requests",
  labelNames: ["service", "method", "path", "code"],
});
app.use((req, res, next) => {
  res.on("finish", () => {
    httpReqs.inc({ service: SERVICE_NAME, method: req.method, path: req.path, code: String(res.statusCode) });
  });
  next();
});

app.get("/health/live", (req, res) => res.status(200).json({ status: "live", service: SERVICE_NAME }));
app.get("/health/ready", (req, res) => res.status(200).json({ status: "ready", service: SERVICE_NAME }));
app.get("/metrics", async (req, res) => {
  res.set("Content-Type", client.register.contentType);
  res.end(await client.register.metrics());
});

app.get("/", (req, res) => res.json({ service: SERVICE_NAME, ok: true }));

app.listen(PORT, "0.0.0.0", () => {
  console.log(`${SERVICE_NAME} listening on :${PORT}`);
});
