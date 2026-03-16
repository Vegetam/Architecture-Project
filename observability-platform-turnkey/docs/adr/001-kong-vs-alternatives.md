# ADR-001 — API Gateway: Kong vs Alternatives

**Date:** 2026-02  
**Status:** Accepted

## Context

This platform needs an API gateway that can:
- Route traffic to services across both the `microservices-ddd-kafka` and `Saga-pattern-architecture` projects
- Inject OpenTelemetry trace context into upstream requests
- Be configured declaratively as code (gitops-friendly)
- Run on both Docker Compose (local dev) and Kubernetes

Candidates evaluated: **Kong OSS**, Nginx + Lua, Traefik, Envoy/Istio, AWS API Gateway.

## Decision

**Kong OSS** — configured declaratively via `deck`.

## Rationale

| Criterion | Kong | Traefik | Envoy/Istio | AWS APIGW |
|---|---|---|---|---|
| Native OTel plugin | ✅ built-in | ✅ (middleware) | ✅ (sidecar) | ❌ custom |
| Declarative config as code | ✅ deck | ✅ file | ✅ xDS | ❌ |
| Kafka-aware routing | ✅ plugins | ❌ | ❌ | ❌ |
| Runs on k8s + Docker | ✅ | ✅ | ✅ | ❌ |
| Complexity | Medium | Low | High | Low |
| OSS & self-hosted | ✅ | ✅ | ✅ | ❌ |

Istio/Envoy was rejected due to operational complexity that would overshadow the actual demonstration of observability patterns. Traefik lacks the native OpenTelemetry Kong plugin and the rate-limiting/JWT ecosystem depth.

## Consequences

- Kong declarative config lives in `gateway/kong.yml`, applied via `deck gateway sync`
- The Kong Prometheus plugin exposes gateway-level metrics (route throughput, upstream health, latency)
- The Kong OpenTelemetry plugin propagates W3C `traceparent` headers to all upstreams — enabling end-to-end traces from gateway to service
