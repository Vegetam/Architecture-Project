#!/usr/bin/env bash
set -euo pipefail

# One-command install for EKS with cloud-native identity.
# Override PROFILE if you want: PROFILE=large ./install-eks.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec env   PROVIDER=aws   AUTH_MODE="${AUTH_MODE:-cloud}"   CLOUD_PROFILE=eks   INSTALL_INGRESS_CONTROLLER="${INSTALL_INGRESS_CONTROLLER:-auto}"   AUTO_STORAGE_CLASS="${AUTO_STORAGE_CLASS:-true}"   PROFILE="${PROFILE:-medium}"   NAMESPACE="${NAMESPACE:-observability}"   "$SCRIPT_DIR/install-observability.sh"
