# Kubernetes production blueprint (hybrid)

This folder provides a **hybrid** deployment model:

- **Dev/local**: MinIO as S3-compatible object storage
- **Prod**: choose one of **S3 / GCS / Azure Blob**
- TLS via **cert-manager**
- Optional mTLS for OTLP ingestion (OpenTelemetry Collector)
- Baseline **NetworkPolicies**
- Backup/restore using **Velero** (scripted restore drill)
- **Cloud profiles** for EKS / GKE / AKS (storage class + topology defaults)

## Quick start (dev/local)

1) Create the namespace and install MinIO:
```bash
kubectl apply -f k8s/manifests/namespace/namespace.yaml
./k8s/scripts/install-minio.sh
```

2) Install the stack:
```bash
PROVIDER=minio PROFILE=small ./k8s/scripts/install-observability.sh
```

## Production install (cloud object storage)

Pick a provider:
- `PROVIDER=aws` (S3 or S3-compatible)
- `PROVIDER=gcp` (GCS)
- `PROVIDER=azure` (Azure Blob)

### Fast path: one command per cloud

These wrappers default to **cloud-native identity** and `PROFILE=medium`:

```bash
./k8s/scripts/install-eks.sh
./k8s/scripts/install-gke.sh
./k8s/scripts/install-aks.sh
```

You can override the size profile:

```bash
PROFILE=large ./k8s/scripts/install-eks.sh
```

### Option A (recommended): cloud-native identity (no static keys)

Set `AUTH_MODE=cloud`:

```bash
# AWS (EKS IRSA)
PROVIDER=aws AUTH_MODE=cloud CLOUD_PROFILE=eks PROFILE=medium ./k8s/scripts/install-observability.sh

# GCP (GKE Workload Identity)
PROVIDER=gcp AUTH_MODE=cloud CLOUD_PROFILE=gke PROFILE=medium ./k8s/scripts/install-observability.sh

# Azure (AKS Workload Identity)
PROVIDER=azure AUTH_MODE=cloud CLOUD_PROFILE=aks PROFILE=medium ./k8s/scripts/install-observability.sh
```

See `k8s/docs/CLOUD_AUTH.md` for the exact Terraform + cluster prerequisites.

### Option B: static keys (discouraged)

1) Provision buckets/containers + lifecycle (Terraform examples in `k8s/infra/`)
2) Provide credentials via External Secrets (recommended) or Kubernetes Secrets
3) Install:
```bash
PROVIDER=aws PROFILE=medium ./k8s/scripts/install-observability.sh
```

Provider overlays live in `k8s/helm-values/providers/`.
Cloud profile overlays live in `k8s/helm-values/cloud-profiles/`.

## TLS with cert-manager (Grafana ingress)

Use the render-aware security helper so placeholders are resolved before `kubectl apply`:

- Let's Encrypt (production):
```bash
LETSENCRYPT_EMAIL=ops@example.com \
GRAFANA_HOSTNAME=grafana.example.com \
./k8s/scripts/apply-security.sh
```

- Self-signed (dev):
```bash
TLS_MODE=selfsigned \
GRAFANA_HOSTNAME=grafana.dev.local \
./k8s/scripts/apply-security.sh
```

## NetworkPolicies

Apply baseline policies:
```bash
./k8s/scripts/apply-security.sh
```

## Backups & restore drills (Velero)

Install Velero:
```bash
# dev/local
PROVIDER=minio ./k8s/scripts/install-velero.sh

# cloud-native identity
PROVIDER=aws AUTH_MODE=cloud ./k8s/scripts/install-velero.sh
```

Run a restore drill:
```bash
OBS_NAMESPACE=observability ./k8s/scripts/restore-drill.sh
```

See runbooks in `k8s/runbooks/`.


## Managed cloud quality-of-life

- `install-observability.sh` auto-installs **ingress-nginx** for **EKS/AKS** when `INSTALL_INGRESS_CONTROLLER=auto` (default) and skips it on **GKE** to use the managed `gce` Ingress.
- `AUTO_STORAGE_CLASS=true` (default) detects the best available StorageClass per cloud and applies an override automatically if your cluster uses a different class name than the opinionated default.
- You can force a class manually with `STORAGE_CLASS_OVERRIDE=<name>`.

## Version pinning and render safety

- `k8s/versions.yaml` is the source of truth for pinned Helm chart versions.
- `k8s/scripts/install-observability.sh` and `k8s/scripts/install-velero.sh` render any `${VAR}` placeholders into temporary values files before running Helm.
- CI runs `k8s/scripts/validate-helm-render.sh` to catch unresolved placeholders and Helm values drift early.
