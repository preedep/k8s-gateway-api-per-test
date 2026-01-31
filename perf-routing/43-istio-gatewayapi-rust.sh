#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib.sh"

need_cmd kubectl

if ! command -v istioctl >/dev/null 2>&1; then
  err "istioctl is required but not found."
  err "Install options:"
  err "- https://istio.io/latest/docs/setup/getting-started/#download"
  err "Then re-run: bash perf-routing/43-istio-gatewayapi-rust.sh"
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
