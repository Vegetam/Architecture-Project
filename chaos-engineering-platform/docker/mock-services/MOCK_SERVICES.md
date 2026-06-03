# Mock Services

These are **intentional mocks** of the real microservices from
[microservices-ddd-kafka](https://github.com/Vegetam/microservices-ddd-kafka).

## Why mocks exist here

The chaos platform needs target services to inject faults into locally (without
spinning up the full microservices stack). These mocks exist solely for that purpose.

## Contract alignment

The mocks expose the same Prometheus metric names as the real services:
- `otel_http_server_duration_count{service_name, http_status_code, ...}`
- `otel_http_server_duration_bucket{service_name, ...}`

This is intentional — the steady-state probes in `analysis/steady-state.yaml` query
these exact metric names. If the real service metric names change, update the mocks
and steady-state probes to match.

## What they are NOT

- Not a source of truth for business logic
- Not kept in sync with the real service implementations beyond the metric contract
- Not used in production — only in local kind clusters and CI

For the real service implementations see:
- [microservices-ddd-kafka](https://github.com/Vegetam/microservices-ddd-kafka)
- [gitops-progressive-delivery/services/](../../../gitops-progressive-delivery/services/)
  (deployment stubs used by the GitOps pipeline)
