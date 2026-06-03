#!/usr/bin/env bash
set -euo pipefail

# One-command install for AKS with cloud-native identity.
# Override PROFILE if you want: PROFILE=large ./install-aks.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec env   PROVIDER=azure   AUTH_MODE="${AUTH_MODE:-cloud}"   CLOUD_PROFILE=aks   INSTALL_INGRESS_CONTROLLER="${INSTALL_INGRESS_CONTROLLER:-auto}"   AUTO_STORAGE_CLASS="${AUTO_STORAGE_CLASS:-true}"   PROFILE="${PROFILE:-medium}"   NAMESPACE="${NAMESPACE:-observability}"   "$SCRIPT_DIR/install-observability.sh"
