#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib.sh"

need_cmd kubectl

MODE="${1:-all}"

info "Cleaning up test namespaces (${APP_NS}, ${TEST_NS})"
kubectl delete ns "${TEST_NS}" --ignore-not-found
kubectl delete ns "${APP_NS}" --ignore-not-found

if [[ "${MODE}" == "all" ]]; then
  info "Cleaning up controllers (ingress-nginx, envoy-gateway-system, istio-system, kong-system)"
  kubectl delete ns ingress-nginx --ignore-not-found
  kubectl delete ns envoy-gateway-system --ignore-not-found
  kubectl delete ns istio-system --ignore-not-found
  kubectl delete ns kong-system --ignore-not-found
fi

info "OK"
