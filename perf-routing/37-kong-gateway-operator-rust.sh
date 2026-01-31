#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib.sh"

need_cmd kubectl
need_cmd helm

KONG_OPERATOR_NS="kong-system"
GW_NAME="kong-rust"
HELM_TIMEOUT="${HELM_TIMEOUT:-15m}"
HELM_RETRIES="${HELM_RETRIES:-3}"
KONG_OPERATOR_CPU_REQUEST="${KONG_OPERATOR_CPU_REQUEST:-1m}"
KONG_OPERATOR_MEM_REQUEST="${KONG_OPERATOR_MEM_REQUEST:-16Mi}"
KONG_OPERATOR_CPU_LIMIT="${KONG_OPERATOR_CPU_LIMIT:-500m}"
KONG_OPERATOR_MEM_LIMIT="${KONG_OPERATOR_MEM_LIMIT:-256Mi}"

print_kong_operator_debug() {
  warn "Helm install/upgrade failed. Collecting diagnostics..."
  kubectl -n "${KONG_OPERATOR_NS}" get pods -o wide || true
  kubectl -n "${KONG_OPERATOR_NS}" get events --sort-by=.lastTimestamp | tail -n 50 || true
  kubectl -n "${KONG_OPERATOR_NS}" describe pods || true
  helm -n "${KONG_OPERATOR_NS}" status kong-operator || true
}

info "Installing Kong Gateway Operator (Gateway API controller) via Helm..."
ensure_ns "${KONG_OPERATOR_NS}"

# Add Kong Helm repository
helm repo add kong https://charts.konghq.com >/dev/null 2>&1 || true
info "Updating Helm repos (this may take a while if network is slow)..."
helm repo update

# Install Kong Gateway Operator using Helm (skip Gateway API CRDs as they're already installed)
set +e
for i in $(seq 1 "${HELM_RETRIES}"); do
  info "Helm install/upgrade attempt ${i}/${HELM_RETRIES} (timeout=${HELM_TIMEOUT})..."
  helm upgrade --install kong-operator kong/gateway-operator \
    -n "${KONG_OPERATOR_NS}" \
    --create-namespace \
    --skip-crds \
    --set "kic-crds.enabled=false" \
    --set "gwapi-standard-crds.enabled=false" \
    --set "gwapi-experimental-crds.enabled=false" \
    --set "resources.requests.cpu=${KONG_OPERATOR_CPU_REQUEST}" \
    --set "resources.requests.memory=${KONG_OPERATOR_MEM_REQUEST}" \
    --set "resources.limits.cpu=${KONG_OPERATOR_CPU_LIMIT}" \
    --set "resources.limits.memory=${KONG_OPERATOR_MEM_LIMIT}" \
    --wait \
    --timeout "${HELM_TIMEOUT}"
  rc=$?
  if [[ $rc -eq 0 ]]; then
    break
  fi
  warn "Helm attempt ${i}/${HELM_RETRIES} failed (exit=${rc}). Retrying..."
  sleep 10
done
set -e

if ! helm -n "${KONG_OPERATOR_NS}" status kong-operator >/dev/null 2>&1; then
  print_kong_operator_debug
  exit 1
fi

kubectl -n "${KONG_OPERATOR_NS}" wait --for=condition=Available=True --timeout="${HELM_TIMEOUT}" deployment --all || {
  print_kong_operator_debug
  exit 1
}

ensure_ns "${APP_NS}"

info "Creating GatewayConfiguration (DataPlane image) with resource limits and high-performance tuning"
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
            env:
            - name: KONG_NGINX_WORKER_PROCESSES
              value: "auto"
            - name: KONG_NGINX_EVENTS_WORKER_CONNECTIONS
              value: "10000"
            - name: KONG_UPSTREAM_KEEPALIVE_POOL_SIZE
              value: "512"
            - name: KONG_UPSTREAM_KEEPALIVE_MAX_REQUESTS
              value: "10000"
            - name: KONG_UPSTREAM_KEEPALIVE_IDLE_TIMEOUT
              value: "60"
            - name: KONG_NGINX_HTTP_KEEPALIVE_REQUESTS
              value: "10000"
            - name: KONG_NGINX_HTTP_KEEPALIVE_TIMEOUT
              value: "75s"
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
