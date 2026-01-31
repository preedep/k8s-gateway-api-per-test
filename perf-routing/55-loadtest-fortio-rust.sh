#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib.sh"

need_cmd kubectl

MODE="${1:-}"
if [[ -z "${MODE}" ]]; then
  err "Usage: bash perf-routing/55-loadtest-fortio-rust.sh <nginx|envoy|istio|kong> [duration] [concurrency] [qps]"
  exit 1
fi

DURATION="${2:-30s}"
CONCURRENCY="${3:-64}"
QPS="${4:-0}"

ensure_ns "${TEST_NS}"

info "Ensuring Fortio runner exists in namespace ${TEST_NS}"
kubectl -n "${TEST_NS}" apply -f - <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fortio
spec:
  replicas: 1
  selector:
    matchLabels:
      app: fortio
  template:
    metadata:
      labels:
        app: fortio
    spec:
      containers:
      - name: fortio
        image: fortio/fortio:latest
        args: ["server"]
        resources:
          requests:
            cpu: "500m"
            memory: "512Mi"
          limits:
            cpu: "2"
            memory: "2Gi"
        ports:
        - containerPort: 8080
YAML

wait_deploy "${TEST_NS}" fortio

TARGET=""

if [[ "${MODE}" == "nginx" ]]; then
  SVC_IP="$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.spec.clusterIP}')"
  TARGET="http://${SVC_IP}/rust-echo"
elif [[ "${MODE}" == "envoy" ]]; then
  ENVOY_SVC="$(envoy_dataplane_svc "${APP_NS}" "eg-rust")"
  if [[ -z "${ENVOY_SVC}" ]]; then
    err "Could not detect Envoy dataplane service. Ensure you ran: bash perf-routing/33-envoy-gateway-rust.sh"
    exit 1
  fi
  SVC_IP="$(kubectl -n envoy-gateway-system get svc "${ENVOY_SVC}" -o jsonpath='{.spec.clusterIP}')"
  TARGET="http://${SVC_IP}/rust-echo"
elif [[ "${MODE}" == "istio" ]]; then
  SVC_NAME="istio-gw-rust-istio"
  if ! kubectl -n "${APP_NS}" get svc "${SVC_NAME}" >/dev/null 2>&1; then
    SVC_NAME="$(kubectl -n "${APP_NS}" get svc -l gateway.networking.k8s.io/gateway-name=istio-gw-rust -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  fi
  if [[ -z "${SVC_NAME}" ]]; then
    err "Could not detect Istio gateway service. Ensure you ran: bash perf-routing/43-istio-gatewayapi-rust.sh"
    exit 1
  fi
  SVC_IP="$(kubectl -n "${APP_NS}" get svc "${SVC_NAME}" -o jsonpath='{.spec.clusterIP}')"
  TARGET="http://${SVC_IP}/rust-echo"
elif [[ "${MODE}" == "kong" ]]; then
  # Kong Gateway Operator creates service with pattern: dataplane-ingress-<gateway-name>-*
  SVC_NAME="$(kubectl -n "${APP_NS}" get svc -l gateway-operator.konghq.com/dataplane-service-type=ingress -o jsonpath='{.items[?(@.metadata.name=~".*kong-rust.*")].metadata.name}' 2>/dev/null || true)"
  if [[ -z "${SVC_NAME}" ]]; then
    # Fallback: try to find by name pattern
    SVC_NAME="$(kubectl -n "${APP_NS}" get svc --no-headers 2>/dev/null | grep 'dataplane-ingress-kong-rust' | awk '{print $1}' | head -1)"
  fi
  if [[ -z "${SVC_NAME}" ]]; then
    err "Could not detect Kong gateway service. Ensure you ran: bash perf-routing/37-kong-gateway-operator-rust.sh"
    exit 1
  fi
  SVC_IP="$(kubectl -n "${APP_NS}" get svc "${SVC_NAME}" -o jsonpath='{.spec.clusterIP}')"
  TARGET="http://${SVC_IP}/rust-echo"
else
  err "Unknown mode: ${MODE}. Expected nginx|envoy|istio|kong"
  exit 1
fi

info "Running Fortio load test for RUST service: mode=${MODE} duration=${DURATION} concurrency=${CONCURRENCY} qps=${QPS}"
info "Target: ${TARGET}"

kubectl -n "${TEST_NS}" exec deploy/fortio -c fortio -- \
  fortio load -t "${DURATION}" -c "${CONCURRENCY}" -qps "${QPS}" "${TARGET}"
