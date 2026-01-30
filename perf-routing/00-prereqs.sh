#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib.sh"

need_cmd kubectl

GATEWAY_API_REF="v1.4.0"

info "Ensuring Gateway API CRDs (ref=${GATEWAY_API_REF}) are installed..."
if kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1; then
  info "Gateway API CRDs already present."
else
  kubectl kustomize "github.com/kubernetes-sigs/gateway-api/config/crd?ref=${GATEWAY_API_REF}" | kubectl apply -f -
fi

kubectl get crd | egrep 'gateways\.gateway\.networking\.k8s\.io|httproutes\.gateway\.networking\.k8s\.io'
info "OK"
