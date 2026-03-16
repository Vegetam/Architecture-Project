# Production-ready hardening checklist

This checklist tracks the last-mile items that turn the repository from a production-grade blueprint into a turnkey operational baseline.

## High priority

### `k8s/scripts/common.sh`
- [x] Added shared render helper for `${VAR}` and `${VAR:-default}` placeholders.
- [x] Added chart version lookup from `k8s/versions.yaml`.
- [ ] Keep helper behavior stable; changing placeholder syntax impacts install and CI flows.

### `k8s/scripts/install-observability.sh`
- [x] Renders selected Helm values into temporary files before `helm upgrade`.
- [x] Fails fast on missing required environment variables.
- [x] Reads pinned chart versions from `k8s/versions.yaml`.
- [x] Applies sensible defaults for MinIO and common AWS S3 flags.
- [ ] In staging/prod, run one install per provider (`minio`, `aws`, `gcp`, `azure`) after every chart version bump.

### `k8s/scripts/install-velero.sh`
- [x] Renders Velero overlays before Helm runs.
- [x] Reads the Velero chart version from `k8s/versions.yaml`.
- [x] Provides a safe default backup bucket name for local/dev.
- [ ] Validate restore drills against your real cloud identity setup after every Velero upgrade.

### `k8s/manifests/ingress/grafana-ingress.yaml`
- [x] Converted to a render-aware template (hostname, issuer, ingress class, namespace).
- [ ] Confirm the chosen ingress class matches the controller installed in each cluster.

### `k8s/manifests/cert-manager/clusterissuer-letsencrypt-prod.yaml`
- [x] Converted to a render-aware template (email, ingress class, ACME server).
- [ ] Replace the default ACME endpoint only if you intentionally use staging or a private ACME service.

### `.github/workflows/ci.yml`
- [x] Added Helm render validation to catch unresolved placeholders early.
- [x] Added Helm lint + template smoke tests for MinIO, AWS/IRSA, and GCP/WI scenarios.
- [ ] Expand CI matrix if you add Azure-specific overlays or new providers.

## Medium priority

### `k8s/versions.yaml`
- [x] Extended to pin `velero`, `certManager`, and `ingressNginx`.
- [x] Now acts as the actual source of truth for install scripts.
- [ ] Keep all chart changes in one PR with CI render validation.

### `k8s/scripts/bootstrap-cert-manager.sh`
- [x] Uses the pinned chart version from `k8s/versions.yaml`.
- [ ] Consider adding values overlays if you need webhook or leader-election tuning.

### `k8s/scripts/bootstrap-ingress.sh`
- [x] Uses the pinned `ingress-nginx` chart version.
- [ ] If you standardize on a managed ingress class other than `nginx`/`gce`, update wrapper defaults and docs together.

### `k8s/scripts/install-minio.sh`
- [x] Uses the pinned MinIO chart version.
- [ ] Keep this dev-only; do not treat MinIO as the default production object store.

### `k8s/scripts/apply-security.sh`
- [x] Stops blindly applying raw example manifests.
- [x] Renders ingress and issuer manifests before `kubectl apply`.
- [x] Renders OTel mTLS cert resources with the selected namespace.
- [ ] Review NetworkPolicies against your CNI, DNS, and ingress namespace before enabling strict production rules.

### `k8s/manifests/cert-manager/otel-mtls-certs.yaml`
- [x] Render-aware namespace and service DNS names.
- [ ] If you replace cert-manager with Vault/PKI, update both this manifest and OTel client rollout docs.

## Low priority

### `k8s/README.md`
- [x] Updated to use render-aware install and security flows.
- [ ] Keep examples synchronized with wrapper scripts as defaults evolve.

### `docs/` and runbooks
- [x] Runbooks already cover backup, DR, retention, capacity, and upgrades.
- [ ] Add environment-specific operator notes (EKS/GKE/AKS) if your team wants one-click on-call guidance.

## Final go-live gate

Before you call this repository fully production-ready in your environment:

1. Run CI successfully on a branch that includes your real provider overlays.
2. Deploy to staging using the exact cloud wrapper you plan to use in production.
3. Run `k8s/scripts/install-velero.sh` and `k8s/scripts/restore-drill.sh` with your real auth mode.
4. Validate Grafana ingress TLS issuance end-to-end.
5. Confirm Loki/Tempo write to the intended object store and retention behaves as expected.
6. Verify alerts fire and route correctly (including meta-monitoring alerts).
