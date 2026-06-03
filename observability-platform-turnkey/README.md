# 🔭 Observability Platform

> Production-grade observability layer for [microservices-ddd-kafka](https://github.com/Vegetam/microservices-ddd-kafka), [Saga-pattern-architecture](https://github.com/Vegetam/Saga-pattern-architecture), and [terraform-multicloud](https://github.com/Vegetam/terraform-multicloud) — distributed tracing, metrics, and structured logs via OpenTelemetry, Grafana, Tempo, and Kong.

[![CI](https://github.com/Vegetam/observability-platform/actions/workflows/ci.yml/badge.svg)](https://github.com/Vegetam/observability-platform/actions/workflows/ci.yml)
[![Security](https://github.com/Vegetam/observability-platform/actions/workflows/security.yml/badge.svg)](https://github.com/Vegetam/observability-platform/actions/workflows/security.yml)
[![License](https://img.shields.io/github/license/Vegetam/observability-platform)](LICENSE)

---

## 🗺️ Architecture

```
                        ┌─────────────────────────────────┐
                        │           CLIENT LAYER          │
                        └──────────────┬──────────────────┘
                                       │ HTTPS
                        ┌──────────────▼──────────────────┐
                        │        API GATEWAY (Kong)       │
                        │  OTel tracing · Rate limiting   │
                        │  JWT auth · Correlation ID      │
                        └──┬──────────────┬───────────────┘
                           │              │
              ┌────────────▼───┐   ┌──────▼──────────────┐
              │microservices   │   │saga-pattern-        │
              │-ddd-kafka      │   │architecture         │
              │OrderSvc        │   │SagaOrchestrator     │
              │PaymentSvc      │   │OrderSvc · PaymentSvc│
              │NotifSvc        │   │InventorySvc         │
              └───────┬────────┘   └──────┬──────────────┘
                      └────────┬──────────┘
                               │ OTLP (gRPC/HTTP)
                    ┌──────────▼──────────────┐
                    │  OpenTelemetry Collector │
                    │  tail sampling · batch   │
                    │  spanmetrics processor   │
                    └──┬──────────┬────────────┘
                       │          │
            ┌──────────▼──┐  ┌────▼───────────────┐
            │   Tempo     │  │    Prometheus       │
            │ (Traces)    │  │  (Metrics + Rules)  │
            │ S3/GCS/     │  │  + Alertmanager     │
            │ Azure Blob  │  └────────┬────────────┘
            └──────┬──────┘          │
                   └────────┬────────┘
                            │
                  ┌──────────▼──────────┐
                  │       Grafana       │
                  │  Services Overview  │
                  │  Saga State Machine │
                  │  Traces · Logs      │
                  └─────────────────────┘
```

---

## 🧩 Stack

| Component | Technology | Purpose |
|---|---|---|
| API Gateway | Kong OSS 3.6 | Routing, auth, rate limiting, trace injection |
| Telemetry hub | OpenTelemetry Collector contrib 0.98 | OTLP receiver, tail sampling, spanmetrics, fan-out |
| Tracing | Grafana Tempo (distributed) | Long-term trace storage on object storage |
| Metrics | Prometheus + kube-prometheus-stack | RED metrics, Kafka lag, infra metrics |
| Logs | Loki + Promtail | Label-based log aggregation, trace correlation |
| Dashboards | Grafana 10 | Services Overview, Saga State Machine |
| Alerting | Prometheus rules + Alertmanager | Critical/warning routing, inhibition rules |
| Backup/DR | Velero | Snapshot + restore drills for observability state |

---

## 🚀 Quick Start (Docker Compose)

```bash
# 1. Configure secrets
cp .env.example .env
# edit .env — change ALL passwords

# 2. Start the stack
docker compose -f docker/docker-compose.yml up -d

# 3. Open Grafana
open http://localhost:3000
# login: GRAFANA_ADMIN_USER / GRAFANA_ADMIN_PASSWORD from .env

# 4. Point your services at the OTel Collector
# OTLP gRPC: localhost:4317
# OTLP HTTP: localhost:4318
```

### Instrument your services (Node.js / TypeScript)

```typescript
// src/tracing.ts — import BEFORE anything else in main.ts
import { NodeSDK } from '@opentelemetry/sdk-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-grpc';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';
import { Resource } from '@opentelemetry/resources';
import { SEMRESATTRS_SERVICE_NAME } from '@opentelemetry/semantic-conventions';

new NodeSDK({
  resource: new Resource({ [SEMRESATTRS_SERVICE_NAME]: process.env.OTEL_SERVICE_NAME }),
  traceExporter: new OTLPTraceExporter({ url: process.env.OTEL_EXPORTER_OTLP_ENDPOINT }),
  instrumentations: [getNodeAutoInstrumentations()],
}).start();
```

### Debug overlay (expose internal ports temporarily)

```bash
docker compose \
  -f docker/docker-compose.yml \
  -f docker/docker-compose.debug.yml \
  up -d
# Grafana :3000 · Prometheus :9090 · Tempo :3200 · Alertmanager :9093
```

---

## ☸️ Kubernetes — Multi-Cloud Deployment

The `k8s/` directory contains a full production blueprint supporting **AWS (EKS)**, **GCP (GKE)**, and **Azure (AKS)** with cloud-native auth (IRSA / Workload Identity).

### One-command install per cloud

```bash
# EKS (AWS)
./k8s/scripts/install-eks.sh

# GKE (GCP)
./k8s/scripts/install-gke.sh

# AKS (Azure)
./k8s/scripts/install-aks.sh
```

Or use the generic installer with explicit options:

```bash
PROVIDER=aws AUTH_MODE=cloud PROFILE=medium \
  ./k8s/scripts/install-observability.sh

# PROVIDER: minio | aws | gcp | azure
# AUTH_MODE: static (access keys) | cloud (IRSA / Workload Identity)
# PROFILE:   small | medium | large
```

### Sizing profiles

| Profile | Use case | Prometheus retention | Replicas |
|---|---|---|---|
| `small` | Dev / staging | 7 days | 1 |
| `medium` | Production (< 50 services) | 15 days | 2 |
| `large` | Production (50+ services) | 30 days | 3+ |

### Object storage backends

| Provider | Loki chunks | Tempo traces | Auth |
|---|---|---|---|
| MinIO | local bucket | local bucket | static keys (dev) |
| AWS S3 | S3 bucket | S3 bucket | IRSA (recommended) |
| GCP GCS | GCS bucket | GCS bucket | Workload Identity |
| Azure Blob | Azure container | Azure container | Workload Identity |

Terraform modules for provisioning buckets + IAM/IRSA roles: `k8s/infra/{aws,gcp,azure}/`.

### Cloud-native auth (no static keys in prod)

See [`k8s/docs/CLOUD_AUTH.md`](k8s/docs/CLOUD_AUTH.md) for IRSA and Workload Identity setup.

---

## 🔐 Security defaults

- Kong Admin API is **never exposed** to the host in any compose profile
- All secrets come from `.env` (local) or Kubernetes Secrets / External Secrets Operator (k8s)
- mTLS between OTel Collector and backends in the Kubernetes deployment (`k8s/helm-values/otel-collector-mtls-values.yaml`)
- NetworkPolicies: default-deny with explicit allow rules per component
- Cert-manager issues OTel mTLS certs (Let's Encrypt in prod, self-signed in kind)

---

## 📊 Dashboards

| Dashboard | Panels |
|---|---|
| **Services Overview** | Request rate · Error rate · P99 latency · Kafka lag · DLQ depth · Kong upstream health |
| **Saga State Machine** | Sagas started/completed/failed · Compensation rate · P99 saga duration · COMPENSATION_FAILED log panel |

---

## 🚨 Alerting

Prometheus rules in `prometheus/rules/`:

| Alert | Severity | Condition |
|---|---|---|
| `High5xxErrorRate` | warning | >5% 5xx for 10 min |
| `HighLatencyP99` | warning | p99 >1s for 10 min |
| `SagaCompensationFailed` | **critical** | Any saga stuck in COMPENSATION_FAILED |
| `OtelCollectorDown` | **critical** | Collector unreachable for 2 min |
| `KafkaDlqHasMessages` | warning | DLQ non-empty for 5 min |
| `InstanceDown` | **critical** | Any Prometheus target down 2 min |
| `LokiDown` | **critical** | Loki unreachable 2 min |
| `TempoDown` | **critical** | Tempo unreachable 2 min |

Alertmanager routes critical alerts immediately (0s group wait), warns with 30s grouping. Inhibition rules suppress warnings when a critical is already firing for the same service.

---

## 💾 Backup & Disaster Recovery

Velero is used to snapshot PVCs and Kubernetes resources:

```bash
# Install Velero (pick your provider)
PROVIDER=aws ./k8s/scripts/install-velero.sh

# Run a restore drill (validates backup integrity)
./k8s/scripts/restore-drill.sh
```

Runbooks in `k8s/runbooks/`: BACKUP_RESTORE · DR · INCIDENTS · CAPACITY · RETENTION · UPGRADE.

---

## 📁 Repository Structure

```
.
├── docker/
│   ├── docker-compose.yml          # Full local stack
│   └── docker-compose.debug.yml    # Debug overlay (exposes internal ports)
│
├── gateway/
│   └── kong.yml                    # Declarative Kong config (deck format)
│
├── otel-collector/
│   └── config.yaml                 # OTel pipeline: receivers → processors → exporters
│
├── prometheus/
│   ├── prometheus.yml              # Scrape configs
│   └── rules/
│       ├── services.yml            # Service-level alerts (RED + Saga + Kafka)
│       └── infra.yml               # Infrastructure alerts (down targets, Loki, Tempo)
│
├── alertmanager/
│   └── config.yml                  # Routing: critical → immediate, warning → grouped
│
├── grafana/
│   ├── provisioning/               # Auto-provisioned datasources + dashboard loader
│   └── dashboards/
│       ├── services-overview.json  # RED metrics + Kafka lag + Kong health
│       └── saga-state-machine.json # Saga counters + compensation rate + log panel
│
├── loki/ tempo/ promtail/          # Component configs
│
├── k8s/
│   ├── helm-values/
│   │   ├── profiles/               # small | medium | large sizing
│   │   ├── providers/              # minio | aws | gcp | azure storage backends
│   │   └── cloud-profiles/         # eks | gke | aks platform defaults
│   ├── infra/{aws,gcp,azure}/      # Terraform: buckets + IAM/IRSA roles
│   ├── manifests/                  # NetworkPolicies, cert-manager, ExternalSecrets, ServiceMonitors
│   ├── runbooks/                   # INCIDENTS, DR, CAPACITY, RETENTION, UPGRADE, BACKUP_RESTORE
│   ├── scripts/                    # install-observability.sh + per-cloud wrappers
│   └── versions.yaml               # Pinned Helm chart versions (single source of truth)
│
├── scripts/
│   ├── kind-up.sh                  # Local kind cluster
│   └── smoke-test.sh               # End-to-end trace validation
│
└── docs/adr/
    ├── 001-kong-vs-alternatives.md
    ├── 002-otel-collector-as-hub.md
    └── 003-loki-for-logs.md
```

---

## 🔗 Related Projects

| Repo | Role |
|---|---|
| [microservices-ddd-kafka](https://github.com/Vegetam/microservices-ddd-kafka) | Instrumented upstream services (OrderSvc, PaymentSvc, NotifSvc) |
| [Saga-pattern-architecture](https://github.com/Vegetam/Saga-pattern-architecture) | Saga orchestrator + participant services |
| [terraform-multicloud](https://github.com/Vegetam/terraform-multicloud) | Provisions EKS/AKS/GKE clusters where this stack deploys |
