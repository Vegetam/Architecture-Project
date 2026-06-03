# Sizing profiles

These are baseline profiles intended as **starting points**. Always validate with real load tests.

- `small`: single-node / low ingest
- `medium`: moderate ingest; enables HPA where practical
- `large`: higher ingest; more replicas; assumes multi-zone cluster

Use with `k8s/scripts/install-observability.sh` via `PROFILE=small|medium|large`.
