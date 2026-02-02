#!/usr/bin/env bash
set -euo pipefail

APP_NS="perf-app"
TEST_NS="perf-test"
MON_NS="perf-monitoring"

# Detect kubectl or microk8s kubectl
if command -v kubectl >/dev/null 2>&1; then
  KUBECTL_CMD="kubectl"
elif command -v microk8s >/dev/null 2>&1; then
  KUBECTL_CMD="microk8s kubectl"
  # Create kubectl wrapper function
  kubectl() {
    microk8s kubectl "$@"
  }
  export -f kubectl
  
  # Export kubeconfig for tools like istioctl
  if [[ -z "${KUBECONFIG:-}" ]]; then
    KUBECONFIG_TEMP="$(mktemp)"
    microk8s config > "${KUBECONFIG_TEMP}" 2>/dev/null || true
    if [[ -s "${KUBECONFIG_TEMP}" ]]; then
      export KUBECONFIG="${KUBECONFIG_TEMP}"
      # Clean up on exit
      trap "rm -f '${KUBECONFIG_TEMP}'" EXIT
    else
      rm -f "${KUBECONFIG_TEMP}"
    fi
  fi
else
  echo "ERROR: neither kubectl nor microk8s command found" >&2
  exit 1
fi

need_cmd() {
  # Skip kubectl check since we handle it above
  if [[ "$1" == "kubectl" ]]; then
    return 0
  fi
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: missing command: $1" >&2
    exit 1
  }
}

ensure_ns() {
  local ns="$1"
  kubectl get ns "$ns" >/dev/null 2>&1 || kubectl create ns "$ns"
}

wait_deploy() {
  local ns="$1" name="$2"
  kubectl -n "$ns" rollout status "deploy/$name" --timeout=5m
}

wait_gateway_programmed() {
  local ns="$1" name="$2"
  kubectl -n "$ns" wait gateway/"$name" --for=condition=Programmed=True --timeout=5m >/dev/null 2>&1 || true
}

envoy_dataplane_svc() {
  local owning_ns="$1" owning_gateway="$2"
  kubectl get svc -n envoy-gateway-system \
    --selector="gateway.envoyproxy.io/owning-gateway-namespace=${owning_ns},gateway.envoyproxy.io/owning-gateway-name=${owning_gateway}" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
}

info() {
  echo "[INFO] $*"
}

warn() {
  echo "[WARN] $*" >&2
}

err() {
  echo "[ERROR] $*" >&2
}
