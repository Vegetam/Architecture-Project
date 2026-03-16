# Capacity planning notes

Capacity depends heavily on:
- log volume (GB/day)
- trace volume (spans/sec)
- metrics cardinality (series count)
- retention requirements

## Practical starting points

- Start with conservative retention (7-15 days) and expand only if you have a clear need.
- Keep an eye on:
  - Loki ingester memory
  - Tempo ingester memory
  - Prometheus series count and TSDB churn
  - object storage request/egress costs

## Sizing workflow

1) Measure ingest rates for 1-2 weeks.
2) Estimate storage needs:
   - logs: (GB/day * retention_days) * 1.2
   - traces: depends on sampling and payload sizes
3) Set SLOs for query latency.
4) Increase replicas and/or shard components to meet SLOs.

## Cardinality control

- Prefer low-cardinality labels.
- Do not label by user_id/session_id/order_id.
- Use exemplars and trace correlation instead of high-cardinality labels.
