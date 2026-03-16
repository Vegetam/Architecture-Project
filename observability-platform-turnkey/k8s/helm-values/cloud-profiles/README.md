# Cloud profiles

Cloud profiles provide **opinionated, cloud-specific defaults** for managed Kubernetes:

- **EKS** (AWS)
- **GKE** (GCP)
- **AKS** (Azure)

They are designed to get you to a production-shaped deployment quickly, with sensible defaults for:

- **Storage classes** (premium tiers by default)
- **StorageClass auto-detection** (falls back to a working class if the expected name is not present)
- **Zone spreading + anti-affinity** (avoid single-node / single-zone failure modes)
- **Ingress class defaults** (Grafana)
- **Ingress controller bootstrapping** (ingress-nginx on EKS/AKS, managed GKE Ingress on GKE)
- **HA defaults** for core components (Prometheus/Alertmanager replicas)

## How profiles combine

The installer applies values in this order:

1. Base chart values
2. Provider overlay (MinIO/S3/GCS/Azure + auth mode)
3. Sizing profile (`small|medium|large`)
4. Cloud profile (`eks|gke|aks`)
5. Generated StorageClass override (if auto-detection is enabled)

Because the cloud profile is applied near the end, it may override parts of the sizing profile.
The generated StorageClass override is applied last so the stack can adapt to clusters that use different class names.

## Storage class defaults

Preferred defaults:

- **EKS**: `gp3`
- **GKE**: `premium-rwo`
- **AKS**: `managed-premium`

If the preferred class does not exist, the installer tries cloud-specific fallbacks first, then the cluster default StorageClass, then the first available StorageClass.
You can force a specific class with:

```bash
STORAGE_CLASS_OVERRIDE=my-storage-class ./k8s/scripts/install-observability.sh
```

## Ingress defaults

- **EKS / AKS**: `INSTALL_INGRESS_CONTROLLER=auto` installs `ingress-nginx` and keeps Grafana on `ingressClassName: nginx`
- **GKE**: `INSTALL_INGRESS_CONTROLLER=auto` skips `ingress-nginx` and uses the managed `gce` Ingress class

You can disable ingress controller bootstrapping entirely with:

```bash
INSTALL_INGRESS_CONTROLLER=false ./k8s/scripts/install-observability.sh
```
