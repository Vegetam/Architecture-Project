# Upgrade runbook

## Principles

- Pin chart/app versions.
- Upgrade in staging first.
- Use `--atomic` and set sensible timeouts.
- Keep rollback paths documented.

## Workflow

1) Update `k8s/versions.yaml`.
2) Run `helm repo update`.
3) In staging, upgrade one component at a time:

```bash
helm upgrade --install loki grafana/loki -n observability -f k8s/helm-values/loki-s3-ha-values.yaml --atomic --timeout 10m
```

4) Validate:
- ingestion OK
- query OK
- dashboards OK
- alert noise OK

5) Roll out to production.

## Rollback

```bash
helm history loki -n observability
helm rollback loki <REVISION> -n observability
```
