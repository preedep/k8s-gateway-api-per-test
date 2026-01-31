#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib.sh"

need_cmd kubectl

usage() {
  cat >&2 <<'EOF'
Usage: 00-prereqs.sh [--no-validate]

Environment:
  KUBECTL_APPLY_VALIDATE=false  Disable kubectl OpenAPI validation (adds --validate=false to apply)
EOF
}

KUBECTL_APPLY_VALIDATE="${KUBECTL_APPLY_VALIDATE:-true}"
for arg in "$@"; do
  case "$arg" in
    --no-validate)
      KUBECTL_APPLY_VALIDATE="false"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      err "Unknown argument: $arg"
      usage
      exit 2
      ;;
  esac
done

KUBECTL_APPLY_VALIDATE_LC="$(printf '%s' "${KUBECTL_APPLY_VALIDATE}" | tr '[:upper:]' '[:lower:]')"
KUBECTL_APPLY_VALIDATE_FLAG=""
case "$KUBECTL_APPLY_VALIDATE_LC" in
  1|true|yes|y)
    KUBECTL_APPLY_VALIDATE_FLAG=""
    ;;
  0|false|no|n)
    KUBECTL_APPLY_VALIDATE_FLAG="--validate=false"
    ;;
  *)
    err "Invalid value for KUBECTL_APPLY_VALIDATE: ${KUBECTL_APPLY_VALIDATE} (expected true/false)"
    exit 2
    ;;
esac

GATEWAY_API_REF="v1.4.0"

KUBE_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"
KUBE_APISERVER="$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || true)"
if [[ -n "$KUBE_CONTEXT" ]]; then
  info "kubectl context: ${KUBE_CONTEXT}"
fi
if [[ -n "$KUBE_APISERVER" ]]; then
  info "kube-apiserver: ${KUBE_APISERVER}"
fi

KUBE_APISERVER_HOST="${KUBE_APISERVER#https://}"
KUBE_APISERVER_HOST="${KUBE_APISERVER_HOST#http://}"
KUBE_APISERVER_HOST="${KUBE_APISERVER_HOST%%/*}"
KUBE_APISERVER_HOST="${KUBE_APISERVER_HOST%%:*}"

if [[ -n "$KUBE_APISERVER_HOST" ]] && command -v nslookup >/dev/null 2>&1; then
  if ! nslookup "$KUBE_APISERVER_HOST" >/dev/null 2>&1; then
    err "Cannot resolve Kubernetes API server hostname: ${KUBE_APISERVER_HOST}"
    err "This is usually caused by missing VPN/private DNS configuration or an unreachable private cluster endpoint."
    err "Current context: ${KUBE_CONTEXT:-<unknown>}"
    err "API server: ${KUBE_APISERVER:-<unknown>}"
    exit 1
  fi
fi

if ! kubectl --request-timeout=5s get --raw=/readyz >/dev/null 2>&1; then
  err "Cannot reach Kubernetes API server via kubectl."
  err "Current context: ${KUBE_CONTEXT:-<unknown>}"
  err "API server: ${KUBE_APISERVER:-<unknown>}"
  err "If this is a private cluster, connect to the required network/VPN and ensure DNS is configured correctly."
  exit 1
fi

info "Ensuring Gateway API CRDs (ref=${GATEWAY_API_REF}) are installed..."
if kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1; then
  info "Gateway API CRDs already present."
else
  kubectl kustomize "github.com/kubernetes-sigs/gateway-api/config/crd?ref=${GATEWAY_API_REF}" | kubectl apply ${KUBECTL_APPLY_VALIDATE_FLAG:+$KUBECTL_APPLY_VALIDATE_FLAG} -f -
fi

kubectl get crd | egrep 'gateways\.gateway\.networking\.k8s\.io|httproutes\.gateway\.networking\.k8s\.io'
info "OK"
