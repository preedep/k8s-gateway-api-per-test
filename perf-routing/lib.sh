#!/usr/bin/env bash
set -euo pipefail

APP_NS="perf-app"
TEST_NS="perf-test"

need_cmd() {
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
