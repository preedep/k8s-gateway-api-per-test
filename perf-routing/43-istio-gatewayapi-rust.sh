#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib.sh"

need_cmd kubectl

ISTIO_VERSION="${ISTIO_VERSION:-1.22.3}"
ISTIOCTL_BIN=""

if command -v istioctl >/dev/null 2>&1; then
  ISTIOCTL_BIN="istioctl"
else
  need_cmd curl
  need_cmd tar

  OS_RAW="$(uname -s)"
  ARCH_RAW="$(uname -m)"

  OS=""
  ARCH=""
  case "${OS_RAW}" in
    Linux) OS="linux" ;;
    Darwin) OS="osx" ;;
    *)
      err "Unsupported OS for istioctl auto-install: ${OS_RAW}"
      exit 1
      ;;
  esac

  case "${ARCH_RAW}" in
    x86_64|amd64) ARCH="amd64" ;;
    arm64|aarch64) ARCH="arm64" ;;
    *)
      err "Unsupported architecture for istioctl auto-install: ${ARCH_RAW}"
      exit 1
      ;;
  esac

  TOOLS_DIR="${SCRIPT_DIR}/../.tools/istioctl/${ISTIO_VERSION}"
  mkdir -p "${TOOLS_DIR}"

  ISTIOCTL_PATH="${TOOLS_DIR}/istioctl"
  if [[ ! -x "${ISTIOCTL_PATH}" ]]; then
    TMP_DIR="$(mktemp -d)"
    ARCHIVE="${TMP_DIR}/istioctl.tar.gz"
    URL="https://github.com/istio/istio/releases/download/${ISTIO_VERSION}/istioctl-${ISTIO_VERSION}-${OS}-${ARCH}.tar.gz"

    info "istioctl not found; downloading ${URL}"
    curl -fsSL "${URL}" -o "${ARCHIVE}"
    tar -xzf "${ARCHIVE}" -C "${TMP_DIR}"
    mv "${TMP_DIR}/istioctl" "${ISTIOCTL_PATH}"
    chmod +x "${ISTIOCTL_PATH}"
    rm -rf "${TMP_DIR}"
  fi

  ISTIOCTL_BIN="${ISTIOCTL_PATH}"
fi

info "Installing Istio (minimal profile) with Gateway API enabled..."
"${ISTIOCTL_BIN}" install -y \
  --set profile=minimal \
  --set values.pilot.env.PILOT_ENABLED_SERVICE_APIS=true

ensure_ns "${APP_NS}"

kubectl label namespace "${APP_NS}" istio-injection=disabled --overwrite >/dev/null 2>&1 || true

info "Ensuring GatewayClass istio exists..."
kubectl apply -f - <<'YAML'
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: istio
spec:
  controllerName: istio.io/gateway-controller
YAML

GW_NAME="istio-gw-rust"

info "Creating Istio Gateway API resources in namespace ${APP_NS} for Rust service"
kubectl -n "${APP_NS}" apply -f - <<YAML
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: ${GW_NAME}
  annotations:
    networking.istio.io/service-type: ClusterIP
spec:
  gatewayClassName: istio
  listeners:
  - name: http
    port: 80
    protocol: HTTP
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: rust-echo-route-istio
spec:
  parentRefs:
  - name: ${GW_NAME}
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /rust-echo
    filters:
    - type: URLRewrite
      urlRewrite:
        path:
          type: ReplacePrefixMatch
          replacePrefixMatch: /echo
    backendRefs:
    - name: rust-echo
      port: 80
YAML

wait_gateway_programmed "${APP_NS}" "${GW_NAME}"

info "Applying EnvoyFilter for high-performance tuning..."
kubectl -n "${APP_NS}" apply -f - <<YAML
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata:
  name: ${GW_NAME}-performance-tuning
spec:
  workloadSelector:
    labels:
      istio.io/gateway-name: ${GW_NAME}
  configPatches:
  - applyTo: CLUSTER
    match:
      context: GATEWAY
    patch:
      operation: MERGE
      value:
        circuit_breakers:
          thresholds:
          - priority: DEFAULT
            max_connections: 10000
            max_pending_requests: 10000
            max_requests: 10000
            max_retries: 3
        upstream_connection_options:
          tcp_keepalive:
            keepalive_time: 300
  - applyTo: LISTENER
    match:
      context: GATEWAY
    patch:
      operation: MERGE
      value:
        per_connection_buffer_limit_bytes: 32768
YAML

info "Patching Istio gateway deployment with resource limits to match nginx baseline..."
# Wait for deployment to be created
for i in {1..30}; do
  if kubectl -n "${APP_NS}" get deployment "${GW_NAME}-istio" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

# Patch deployment with resource limits and replicas
kubectl -n "${APP_NS}" patch deployment "${GW_NAME}-istio" --type='strategic' -p '{
  "spec": {
    "replicas": 1,
    "template": {
      "spec": {
        "containers": [
          {
            "name": "istio-proxy",
            "resources": {
              "limits": {
                "cpu": "1",
                "memory": "1Gi"
              }
            }
          }
        ]
      }
    }
  }
}' || warn "Could not patch Istio gateway deployment resources"

kubectl -n "${APP_NS}" rollout status deployment "${GW_NAME}-istio" --timeout=2m || true

info "Generated gateway Service/Deployment are typically named <Gateway>-<GatewayClass>"
info "Expected Service: ${APP_NS}/${GW_NAME}-istio"

kubectl -n "${APP_NS}" get gateway,httproute || true
kubectl -n "${APP_NS}" get svc | egrep "${GW_NAME}-istio|NAME" || true

info "OK"
