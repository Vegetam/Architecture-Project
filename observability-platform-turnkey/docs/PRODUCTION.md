# Production readiness guide

This repo ships two modes:

- **Docker Compose**: local/dev/demo
- **Kubernetes blueprint**: production direction (HA + object storage + security)

## What "production-ready" means here

In real environments, "production-ready" is not a single switch. It is a set of engineering decisions:

- HA for critical components
- durable storage (object storage)
- secrets management
- TLS/mTLS, authn/authz, and network controls
- backups, restore tests, DR runbooks
- upgrade strategy and change management

This repository provides a production-minded baseline and a Kubernetes blueprint in `k8s/`.

## Recommended deployment target

If you need actual HA and secure operations, Kubernetes is strongly recommended.

See:
- `k8s/README.md`
- `k8s/runbooks/`
