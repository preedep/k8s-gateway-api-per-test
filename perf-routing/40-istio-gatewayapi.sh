#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib.sh"

need_cmd kubectl

if ! command -v istioctl >/dev/null 2>&1; then
  err "istioctl is required but not found."
  err "Install options:"
  err "- https://istio.io/latest/docs/setup/getting-started/#download"
  err "Then re-run: bash perf-routing/40-istio-gatewayapi.sh"
  exit 1
fi

info "Installing Istio (minimal profile) with Gateway API enabled..."
istioctl install -y \
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

GW_NAME="istio-gw"

info "Creating Istio Gateway API resources in namespace ${APP_NS}"
kubectl -n "${APP_NS}" apply -f - <<YAML
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: ${GW_NAME}
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
  name: echo-route-istio
spec:
  parentRefs:
  - name: ${GW_NAME}
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /echo
    backendRefs:
    - name: echo
      port: 80
YAML

wait_gateway_programmed "${APP_NS}" "${GW_NAME}"

info "Generated gateway Service/Deployment are typically named <Gateway>-<GatewayClass>"
info "Expected Service: ${APP_NS}/${GW_NAME}-istio"

kubectl -n "${APP_NS}" get gateway,httproute || true
kubectl -n "${APP_NS}" get svc | egrep "${GW_NAME}-istio|NAME" || true

info "OK"
