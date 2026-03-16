# ADR-002 — OTel Collector as Central Telemetry Hub

**Date:** 2026-02  
**Status:** Accepted

## Context

Each service could export telemetry directly to Tempo, Prometheus, and Loki. However, with 6+ services across two projects, this creates tight coupling between services and their telemetry backends.

## Decision

All services send telemetry **only to the OTel Collector** via OTLP. The Collector fans out to Tempo, Prometheus, and Loki.

```
Services → OTel Collector → Tempo
                          → Prometheus
                          → Loki
```

## Rationale

- **Decoupling:** services don't need to know about Tempo, Prometheus, or Loki — only one OTLP endpoint
- **Tail sampling:** the Collector can make sampling decisions on complete traces, keeping 100% of error traces and sampling 10% of successful ones
- **Span metrics:** the `spanmetrics` processor automatically derives RED metrics from traces — no manual Prometheus instrumentation needed for basic request rate/latency/errors
- **Backend flexibility:** swap Tempo for Tempo, or Prometheus for Mimir, by changing one Collector config — zero service changes
- **Buffering:** the Collector can buffer and retry exports, protecting against backend downtime

## Consequences

- Services must include the OTel SDK (Node.js: `@opentelemetry/sdk-node`, Java: Micrometer + OTel bridge)
- The `tracing.ts` bootstrap file must be the first import in each service's entrypoint
- `OTEL_EXPORTER_OTLP_ENDPOINT` environment variable controls the Collector address per environment
