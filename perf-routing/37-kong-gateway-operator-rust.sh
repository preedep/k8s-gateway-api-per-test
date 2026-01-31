#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib.sh"

need_cmd kubectl

KONG_OPERATOR_NS="kong-system"
GW_NAME="kong-rust"

info "Installing Kong Gateway Operator (Gateway API controller)..."
ensure_ns "${KONG_OPERATOR_NS}"

# Official release manifest (kubectl apply). If this URL changes, use the Kong/kong-operator releases page.
kubectl apply -f https://github.com/Kong/kong-operator/releases/latest/download/kong-operator.yaml

kubectl -n "${KONG_OPERATOR_NS}" wait --for=condition=Available=True --timeout=5m deployment --all

ensure_ns "${APP_NS}"

info "Creating GatewayConfiguration (DataPlane image) with resource limits to match nginx baseline"
kubectl -n "${APP_NS}" apply -f - <<'YAML'
apiVersion: gateway-operator.konghq.com/v2beta1
kind: GatewayConfiguration
metadata:
  name: kong-rust
spec:
  dataPlaneOptions:
    deployment:
      replicas: 1
      podTemplateSpec:
        spec:
          containers:
          - name: proxy
            image: kong:3.9.1
            resources:
              limits:
                cpu: "1"
                memory: "1Gi"
YAML

info "Ensuring GatewayClass kong exists..."
kubectl apply -f - <<YAML
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: kong
spec:
  controllerName: konghq.com/gateway-operator
  parametersRef:
    group: gateway-operator.konghq.com
    kind: GatewayConfiguration
    name: kong-rust
    namespace: ${APP_NS}
YAML

info "Creating Gateway + HTTPRoute in namespace ${APP_NS} for Rust service"
kubectl -n "${APP_NS}" apply -f - <<YAML
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: ${GW_NAME}
spec:
  gatewayClassName: kong
  listeners:
  - name: http
    protocol: HTTP
    port: 80
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: rust-echo-route-kong
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

info "Kong dataplane Service is created in the same namespace and labeled with gateway.networking.k8s.io/gateway-name"
kubectl -n "${APP_NS}" get svc -l gateway.networking.k8s.io/gateway-name=${GW_NAME} -o wide || true
kubectl -n "${APP_NS}" get gateway,httproute || true

info "OK"
