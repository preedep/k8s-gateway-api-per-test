#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib.sh"

need_cmd kubectl

EG_VERSION="v1.6.3"
EG_NS="envoy-gateway-system"
GW_NAME="eg-rust"

info "Installing Envoy Gateway ${EG_VERSION} (YAML install)..."
kubectl apply --server-side -f "https://github.com/envoyproxy/gateway/releases/download/${EG_VERSION}/install.yaml"

kubectl wait --timeout=5m -n "${EG_NS}" deployment/envoy-gateway --for=condition=Available

info "Ensuring GatewayClass envoy exists..."
kubectl apply -f - <<'YAML'
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: envoy
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
YAML

ensure_ns "${APP_NS}"

info "Creating EnvoyProxy custom resource for resource limits to match nginx baseline..."
kubectl -n "${APP_NS}" apply -f - <<YAML
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
metadata:
  name: custom-proxy-config
spec:
  provider:
    type: Kubernetes
    kubernetes:
      envoyDeployment:
        replicas: 1
        container:
          resources:
            limits:
              cpu: "1"
              memory: "1Gi"
YAML

info "Creating Gateway+HTTPRoute in namespace ${APP_NS} for Rust service"
kubectl -n "${APP_NS}" apply -f - <<YAML
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: ${GW_NAME}
  annotations:
    gateway.envoyproxy.io/envoy-proxy: custom-proxy-config
spec:
  gatewayClassName: envoy
  listeners:
  - name: http
    port: 80
    protocol: HTTP
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: rust-echo-route
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

ENVOY_SVC="$(envoy_dataplane_svc "${APP_NS}" "${GW_NAME}")"
if [[ -z "${ENVOY_SVC}" ]]; then
  warn "Could not auto-detect Envoy dataplane Service yet. It may take a bit."
  warn "Try: kubectl get svc -n ${EG_NS} --selector=gateway.envoyproxy.io/owning-gateway-namespace=${APP_NS},gateway.envoyproxy.io/owning-gateway-name=${GW_NAME}"
else
  info "Envoy dataplane Service: ${EG_NS}/${ENVOY_SVC}"
  kubectl -n "${EG_NS}" get svc "${ENVOY_SVC}"
fi

kubectl -n "${APP_NS}" get gateway,httproute
info "OK"
