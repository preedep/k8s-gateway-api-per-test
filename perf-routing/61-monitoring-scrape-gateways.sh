#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib.sh"

need_cmd kubectl

ensure_ns "${MON_NS}"

# NGINX Ingress Controller metrics (controller exposes :10254/metrics)
if kubectl get ns ingress-nginx >/dev/null 2>&1; then
  kubectl -n ingress-nginx apply -f - <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: ingress-nginx-controller-metrics
  labels:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/component: controller
spec:
  selector:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/component: controller
  ports:
  - name: metrics
    port: 10254
    targetPort: 10254
YAML

  kubectl -n "${MON_NS}" apply -f - <<'YAML'
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: nginx-ingress-controller
spec:
  namespaceSelector:
    matchNames:
    - ingress-nginx
  selector:
    matchLabels:
      app.kubernetes.io/name: ingress-nginx
      app.kubernetes.io/component: controller
  endpoints:
  - port: metrics
    path: /metrics
    interval: 15s
YAML
else
  warn "Namespace ingress-nginx not found; skipping NGINX ServiceMonitor"
fi

# Envoy Gateway dataplane metrics (admin :19001/stats/prometheus)
if kubectl get ns envoy-gateway-system >/dev/null 2>&1; then
  for GW in eg eg-rust; do
    kubectl -n envoy-gateway-system apply -f - <<YAML
apiVersion: v1
kind: Service
metadata:
  name: envoy-proxy-metrics-${GW}
  labels:
    app.kubernetes.io/name: envoy-gateway
    app.kubernetes.io/component: dataplane
    gateway-name: ${GW}
spec:
  selector:
    gateway.envoyproxy.io/owning-gateway-namespace: ${APP_NS}
    gateway.envoyproxy.io/owning-gateway-name: ${GW}
  ports:
  - name: metrics
    port: 19001
    targetPort: 19001
YAML

    kubectl -n "${MON_NS}" apply -f - <<YAML
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: envoy-proxy-${GW}
spec:
  namespaceSelector:
    matchNames:
    - envoy-gateway-system
  selector:
    matchLabels:
      gateway-name: ${GW}
  endpoints:
  - port: metrics
    path: /stats/prometheus
    interval: 15s
YAML
  done
else
  warn "Namespace envoy-gateway-system not found; skipping Envoy ServiceMonitors"
fi


# Istio Gateway metrics (best-effort; gateway pods usually expose :15090/stats/prometheus)
if kubectl get ns "${APP_NS}" >/dev/null 2>&1; then
  for GW in istio-gw istio-gw-rust; do
    if kubectl -n "${APP_NS}" get pods -l "gateway.networking.k8s.io/gateway-name=${GW}" >/dev/null 2>&1; then
      kubectl -n "${APP_NS}" apply -f - <<YAML
apiVersion: v1
kind: Service
metadata:
  name: istio-gateway-metrics-${GW}
  labels:
    app: istio-gateway-metrics
    gateway-name: ${GW}
spec:
  selector:
    gateway.networking.k8s.io/gateway-name: ${GW}
  ports:
  - name: metrics
    port: 15090
    targetPort: 15090
YAML

      kubectl -n "${MON_NS}" apply -f - <<YAML
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: istio-gateway-${GW}
spec:
  namespaceSelector:
    matchNames:
    - ${APP_NS}
  selector:
    matchLabels:
      gateway-name: ${GW}
  endpoints:
  - port: metrics
    path: /stats/prometheus
    interval: 15s
YAML
    fi
  done
fi

# Kong Gateway metrics (best-effort; requires Kong to expose /metrics)
# If Kong Status API is enabled, /metrics is commonly served on :8100/metrics.
if kubectl get ns "${APP_NS}" >/dev/null 2>&1; then
  for GW in kong kong-rust; do
    if kubectl -n "${APP_NS}" get pods -l "gateway.networking.k8s.io/gateway-name=${GW}" >/dev/null 2>&1; then
      kubectl -n "${APP_NS}" apply -f - <<YAML
apiVersion: v1
kind: Service
metadata:
  name: kong-gateway-metrics-${GW}
  labels:
    app: kong-metrics
    gateway-name: ${GW}
spec:
  selector:
    gateway.networking.k8s.io/gateway-name: ${GW}
  ports:
  - name: metrics
    port: 8100
    targetPort: 8100
YAML

      kubectl -n "${MON_NS}" apply -f - <<YAML
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: kong-gateway-${GW}
spec:
  namespaceSelector:
    matchNames:
    - ${APP_NS}
  selector:
    matchLabels:
      gateway-name: ${GW}
  endpoints:
  - port: metrics
    path: /metrics
    interval: 15s
YAML
    fi
  done
fi

info "Applied ServiceMonitors (where possible). Check Prometheus targets in Grafana/Prometheus UI."
