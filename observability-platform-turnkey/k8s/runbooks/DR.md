# Disaster recovery (DR) runbook

## Goal

Restore observability service after a cluster loss.

## Minimum inputs

- Backups of Kubernetes objects (Velero)
- Access to object storage buckets (Loki/Tempo/Thanos)
- DNS + TLS certificates/issuers

## High-level steps

1) Provision a new cluster and networking.
2) Install cert-manager and your Ingress controller.
3) Restore the `observability` namespace with Velero.
4) Reconnect the stack to existing object storage buckets.
5) Validate ingestion + querying.

## Validation checklist

- Grafana login works (SSO preferred)
- Prometheus is scraping targets
- Loki queries return logs
- Tempo queries return traces
- Alerts fire and route to the right on-call channel
