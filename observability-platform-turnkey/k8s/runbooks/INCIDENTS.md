# Incident response notes

## Triage checklist

1) Is Grafana reachable?
2) Are Prometheus targets up?
3) Are logs/traces ingesting?
4) Is object storage reachable?

## Common failure modes

### Ingestion stops (OTLP)

- Check OTel Collector pod logs
- Verify mTLS client certs (expiration, correct CA)
- Verify NetworkPolicies allow ingress from application namespaces

### Loki query returns nothing

- Check Loki components are Ready
- Verify object storage credentials and bucket access
- Check compactor health

### Tempo traces missing

- Check Tempo distributor/ingesters
- Verify object storage credentials
- Validate OTel exporter endpoint

## Post-incident

- Add/adjust alerts
- Link dashboards to runbooks
- Run a restore test if data integrity was affected
