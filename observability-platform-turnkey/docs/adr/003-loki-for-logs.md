# ADR-003 — Loki over ELK for Log Aggregation

**Date:** 2026-02  
**Status:** Accepted

## Context

Logs from 6+ services need to be aggregated, queryable, and correlated with traces (via `traceId`).

Candidates: **Loki + Promtail**, ELK Stack (Elasticsearch + Logstash + Kibana), OpenSearch.

## Decision

**Grafana Loki** with Promtail as the log shipper.

## Rationale

| Criterion | Loki | ELK | OpenSearch |
|---|---|---|---|
| Resource usage | Very low (index-free) | High (Elasticsearch) | High |
| Grafana integration | Native | Plugin | Plugin |
| Trace correlation | Native (via derived fields) | Manual | Manual |
| Cost (self-hosted) | Low | High | High |
| Full-text indexing | Labels only (not full text) | ✅ full text | ✅ full text |
| Setup complexity | Low | High | High |

For this PoC — and for most microservice observability needs — label-based filtering (service, level, traceId) is sufficient. Full-text search across log bodies is not a requirement here.

The native Grafana integration means clicking a trace in Tempo automatically queries Loki for logs in the same time window from the same service — with zero configuration beyond the datasource definition.

## Consequences

- Services should log structured JSON (one JSON object per line) to stdout
- `traceId` and `correlationId` must be included in every log line for automatic correlation
- Loki is not suitable for compliance log archives requiring full-text search — use object storage (S3) for that use case
