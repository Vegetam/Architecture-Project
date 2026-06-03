# Backup & restore runbook

This runbook describes a baseline backup/restore strategy for the observability stack.

## What to back up

1) **Cluster objects** (Helm releases, CRDs, Deployments, Services, Ingress, Secrets)
2) **Persistent volumes** (Prometheus TSDB, Grafana DB)
3) **Object storage buckets** (Loki chunks/index, Tempo blocks, Thanos blocks)

## Recommended tooling

- **Velero** (cluster objects + PV snapshots)
- Cloud-native bucket policies + lifecycle rules (for object storage)

## Backup procedure (example)

1) Ensure Velero is installed and configured with permissions to your backup bucket.
2) Run a scheduled backup:

```bash
velero schedule create obs-daily --schedule "0 2 * * *" --include-namespaces observability
```

3) Validate backups regularly:

```bash
velero backup get
velero backup describe obs-daily-<timestamp> --details
```

## Restore test (required)

At least once per quarter:

1) Spin up a staging cluster.
2) Restore the namespace:

```bash
velero restore create --from-backup <backup-name>
```

3) Verify:
- Grafana can query Prometheus/Loki/Tempo
- Alerts fire (use a synthetic rule)
- OTLP ingestion works

## Notes

- Object storage is your source of truth for logs/traces (and optionally metrics). Treat it as critical infrastructure.
- Always test restore. A backup that was never restored is not a backup.
