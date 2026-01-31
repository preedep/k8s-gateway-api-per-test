#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib.sh"

need_cmd kubectl
need_cmd helm

KONG_OPERATOR_NS="kong-system"
GW_NAME="kong-rust"

info "Installing Kong Gateway Operator (Gateway API controller) via Helm..."
ensure_ns "${KONG_OPERATOR_NS}"

# Add Kong Helm repository
helm repo add kong https://charts.konghq.com >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1

# Install Kong Gateway Operator using Helm (skip Gateway API CRDs as they're already installed)
helm upgrade --install kong-operator kong/gateway-operator \
  -n "${KONG_OPERATOR_NS}" \
  --create-namespace \
  --skip-crds \
  --wait \
  --timeout 5m

kubectl -n "${KONG_OPERATOR_NS}" wait --for=condition=Available=True --timeout=5m deployment --all

ensure_ns "${APP_NS}"

info "Creating GatewayConfiguration (DataPlane image) with resource limits to match nginx baseline"
kubectl -n "${APP_NS}" apply -f - <<'YAML'
apiVersion: gateway-operator.konghq.com/v1beta1
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
    network:
      services:
        ingress:
          type: ClusterIP
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

info "Enabling Kong Prometheus plugin for metrics collection..."
kubectl apply -f - <<'YAML'
apiVersion: configuration.konghq.com/v1
kind: KongClusterPlugin
metadata:
  name: prometheus
  annotations:
    kubernetes.io/ingress.class: kong
  labels:
    global: "true"
plugin: prometheus
config:
  status_code_metrics: true
  latency_metrics: true
  bandwidth_metrics: true
  upstream_health_metrics: true
YAML

info "Kong dataplane Service is created in the same namespace and labeled with gateway.networking.k8s.io/gateway-name"
kubectl -n "${APP_NS}" get svc -l gateway.networking.k8s.io/gateway-name=${GW_NAME} -o wide || true
kubectl -n "${APP_NS}" get gateway,httproute || true

info "OK"
