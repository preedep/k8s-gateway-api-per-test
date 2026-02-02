#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib.sh"

need_cmd kubectl
need_cmd helm

ensure_ns "${MON_NS}"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo update >/dev/null

helm upgrade --install kps prometheus-community/kube-prometheus-stack \
  -n "${MON_NS}" \
  --wait \
  --atomic \
  --timeout 10m \
  --set nodeExporter.enabled=false \
  -f - <<'YAML'
prometheus:
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    serviceMonitorNamespaceSelector: {}
    podMonitorNamespaceSelector: {}

grafana:
  adminUser: admin
  adminPassword: admin
  sidecar:
    dashboards:
      enabled: true
      label: grafana_dashboard
      searchNamespace: ALL
YAML

kubectl -n "${MON_NS}" apply -f - <<'YAML'
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-nginx
  labels:
    grafana_dashboard: "1"
data:
  nginx.json: |
    {
      "annotations": {"list": []},
      "editable": true,
      "gnetId": null,
      "graphTooltip": 0,
      "id": null,
      "links": [],
      "panels": [
        {
          "datasource": "Prometheus",
          "fieldConfig": {"defaults": {}, "overrides": []},
          "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
          "id": 1,
          "targets": [
            {"expr": "sum(rate(nginx_ingress_controller_nginx_process_requests_total[1m]))", "legendFormat": "req/s"}
          ],
          "title": "NGINX - TPS (req/s)",
          "type": "timeseries"
        },
        {
          "datasource": "Prometheus",
          "fieldConfig": {"defaults": {}, "overrides": []},
          "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0},
          "id": 2,
          "targets": [
            {"expr": "sum(nginx_ingress_controller_connections{state=\"active\"})", "legendFormat": "active connections"}
          ],
          "title": "NGINX - Active Connections",
          "type": "timeseries"
        },
        {
          "datasource": "Prometheus",
          "fieldConfig": {"defaults": {"unit": "percent", "min": 0, "max": 100}, "overrides": []},
          "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
          "id": 3,
          "targets": [
            {"expr": "sum(rate(container_cpu_usage_seconds_total{namespace=\"ingress-nginx\",pod=~\"ingress-nginx-controller.*\",container!=\"POD\"}[5m])) * 100", "legendFormat": "cpu usage"}
          ],
          "title": "NGINX - CPU (%)",
          "type": "timeseries"
        },
        {
          "datasource": "Prometheus",
          "fieldConfig": {"defaults": {"unit": "decmbytes", "min": 0}, "overrides": []},
          "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8},
          "id": 4,
          "targets": [
            {"expr": "sum(container_memory_working_set_bytes{namespace=\"ingress-nginx\",pod=~\"ingress-nginx-controller.*\",container!=\"POD\"}) / 1024 / 1024", "legendFormat": "memory"}
          ],
          "title": "NGINX - Memory (MB)",
          "type": "timeseries"
        },
        {
          "datasource": "Prometheus",
          "fieldConfig": {"defaults": {"unit": "short", "min": 0}, "overrides": []},
          "gridPos": {"h": 8, "w": 6, "x": 0, "y": 16},
          "id": 5,
          "targets": [
            {"expr": "sum(rate(nginx_ingress_controller_nginx_process_requests_total[1m]))", "legendFormat": "total requests"}
          ],
          "title": "NGINX - Request Count (1m)",
          "type": "stat"
        },
        {
          "datasource": "Prometheus",
          "fieldConfig": {"defaults": {"unit": "percentunit", "max": 1, "min": 0}, "overrides": []},
          "gridPos": {"h": 8, "w": 6, "x": 6, "y": 16},
          "id": 6,
          "targets": [
            {"expr": "sum(rate(nginx_ingress_controller_requests{status=~\"5..\"}[1m])) / sum(rate(nginx_ingress_controller_requests[1m]))", "legendFormat": "5xx error rate"}
          ],
          "title": "NGINX - Error Rate (5xx)",
          "type": "stat"
        },
        {
          "datasource": "Prometheus",
          "fieldConfig": {"defaults": {"unit": "short", "min": 0}, "overrides": []},
          "gridPos": {"h": 8, "w": 12, "x": 12, "y": 16},
          "id": 7,
          "targets": [
            {"expr": "sum(nginx_ingress_controller_connections{state=\"active\"})", "legendFormat": "active connections"}
          ],
          "title": "NGINX - Active Connections",
          "type": "timeseries"
        }
      ],
      "refresh": "10s",
      "schemaVersion": 38,
      "style": "dark",
      "tags": ["gateway", "nginx"],
      "templating": {"list": []},
      "time": {"from": "now-15m", "to": "now"},
      "timepicker": {},
      "timezone": "browser",
      "title": "Gateway - NGINX",
      "uid": "gw-nginx",
      "version": 1
    }
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-envoy
  labels:
    grafana_dashboard: "1"
data:
  envoy.json: |
    {
      "annotations": {"list": []},
      "editable": true,
      "graphTooltip": 0,
      "id": null,
      "links": [],
      "panels": [
        {
          "datasource": "Prometheus",
          "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
          "id": 1,
          "targets": [
            {"expr": "sum(rate(envoy_http_downstream_rq_total[1m]))", "legendFormat": "req/s"}
          ],
          "title": "Envoy - TPS (req/s)",
          "type": "timeseries"
        },
        {
          "datasource": "Prometheus",
          "fieldConfig": {"defaults": {"unit": "ms", "min": 0}, "overrides": []},
          "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0},
          "id": 2,
          "targets": [
            {"expr": "histogram_quantile(0.95, sum(rate(envoy_http_downstream_rq_time_bucket[5m])) by (le))", "legendFormat": "p95"},
            {"expr": "histogram_quantile(0.99, sum(rate(envoy_http_downstream_rq_time_bucket[5m])) by (le))", "legendFormat": "p99"}
          ],
          "title": "Envoy - Latency (p95/p99) ms",
          "type": "timeseries"
        },
        {
          "datasource": "Prometheus",
          "fieldConfig": {"defaults": {"unit": "percent", "min": 0, "max": 100}, "overrides": []},
          "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
          "id": 3,
          "targets": [
            {"expr": "sum(rate(container_cpu_usage_seconds_total{namespace=\"envoy-gateway-system\",container!=\"POD\"}[5m])) * 100", "legendFormat": "cpu usage"}
          ],
          "title": "Envoy - CPU (%)",
          "type": "timeseries"
        },
        {
          "datasource": "Prometheus",
          "fieldConfig": {"defaults": {"unit": "decmbytes", "min": 0}, "overrides": []},
          "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8},
          "id": 4,
          "targets": [
            {"expr": "sum(container_memory_working_set_bytes{namespace=\"envoy-gateway-system\",container!=\"POD\"}) / 1024 / 1024", "legendFormat": "memory"}
          ],
          "title": "Envoy - Memory (MB)",
          "type": "timeseries"
        }
      ],
      "refresh": "10s",
      "schemaVersion": 38,
      "style": "dark",
      "tags": ["gateway", "envoy"],
      "templating": {"list": []},
      "time": {"from": "now-15m", "to": "now"},
      "timezone": "browser",
      "title": "Gateway - Envoy",
      "uid": "gw-envoy",
      "version": 1
    }
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-istio
  labels:
    grafana_dashboard: "1"
data:
  istio.json: |
    {
      "annotations": {"list": []},
      "editable": true,
      "graphTooltip": 0,
      "id": null,
      "links": [],
      "panels": [
        {
          "datasource": "Prometheus",
          "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
          "id": 1,
          "targets": [
            {"expr": "sum(rate(istio_requests_total[1m]))", "legendFormat": "req/s"}
          ],
          "title": "Istio - TPS (req/s)",
          "type": "timeseries"
        },
        {
          "datasource": "Prometheus",
          "fieldConfig": {"defaults": {"unit": "s", "min": 0}, "overrides": []},
          "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0},
          "id": 2,
          "targets": [
            {"expr": "histogram_quantile(0.95, sum(rate(istio_request_duration_milliseconds_bucket[5m])) by (le)) / 1000", "legendFormat": "p95"},
            {"expr": "histogram_quantile(0.99, sum(rate(istio_request_duration_milliseconds_bucket[5m])) by (le)) / 1000", "legendFormat": "p99"}
          ],
          "title": "Istio - Latency (p95/p99) sec",
          "type": "timeseries"
        },
        {
          "datasource": "Prometheus",
          "fieldConfig": {"defaults": {"unit": "percent", "min": 0, "max": 100}, "overrides": []},
          "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
          "id": 3,
          "targets": [
            {"expr": "sum(rate(container_cpu_usage_seconds_total{namespace=\"perf-app\",pod=~\"istio-gw.*\",container!=\"POD\"}[5m])) * 100", "legendFormat": "cpu usage"}
          ],
          "title": "Istio Gateway - CPU (%)",
          "type": "timeseries"
        },
        {
          "datasource": "Prometheus",
          "fieldConfig": {"defaults": {"unit": "decmbytes", "min": 0}, "overrides": []},
          "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8},
          "id": 4,
          "targets": [
            {"expr": "sum(container_memory_working_set_bytes{namespace=\"perf-app\",pod=~\"istio-gw.*\",container!=\"POD\"}) / 1024 / 1024", "legendFormat": "memory"}
          ],
          "title": "Istio Gateway - Memory (MB)",
          "type": "timeseries"
        }
      ],
      "refresh": "10s",
      "schemaVersion": 38,
      "style": "dark",
      "tags": ["gateway", "istio"],
      "templating": {"list": []},
      "time": {"from": "now-15m", "to": "now"},
      "timezone": "browser",
      "title": "Gateway - Istio",
      "uid": "gw-istio",
      "version": 1
    }
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-istio-ambient
  labels:
    grafana_dashboard: "1"
data:
  istio-ambient.json: |
    {
      "annotations": {"list": []},
      "editable": true,
      "graphTooltip": 0,
      "id": null,
      "links": [],
      "panels": [
        {
          "datasource": "Prometheus",
          "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
          "id": 1,
          "targets": [
            {"expr": "sum(rate(istio_requests_total{source_workload_namespace=\"perf-app\"}[1m]))", "legendFormat": "req/s"}
          ],
          "title": "Istio Ambient - TPS (req/s)",
          "type": "timeseries"
        },
        {
          "datasource": "Prometheus",
          "fieldConfig": {"defaults": {"unit": "s", "min": 0}, "overrides": []},
          "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0},
          "id": 2,
          "targets": [
            {"expr": "histogram_quantile(0.95, sum(rate(istio_request_duration_milliseconds_bucket{source_workload_namespace=\"perf-app\"}[5m])) by (le)) / 1000", "legendFormat": "p95"},
            {"expr": "histogram_quantile(0.99, sum(rate(istio_request_duration_milliseconds_bucket{source_workload_namespace=\"perf-app\"}[5m])) by (le)) / 1000", "legendFormat": "p99"}
          ],
          "title": "Istio Ambient - Latency (p95/p99) sec",
          "type": "timeseries"
        },
        {
          "datasource": "Prometheus",
          "fieldConfig": {"defaults": {"unit": "percent", "min": 0, "max": 100}, "overrides": []},
          "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
          "id": 3,
          "targets": [
            {"expr": "sum(rate(container_cpu_usage_seconds_total{namespace=\"perf-app\",pod=~\"istio-ambient-gw.*\",container!=\"POD\"}[5m])) * 100", "legendFormat": "gateway cpu"},
            {"expr": "sum(rate(container_cpu_usage_seconds_total{namespace=\"istio-system\",pod=~\"ztunnel.*\",container!=\"POD\"}[5m])) * 100", "legendFormat": "ztunnel cpu"}
          ],
          "title": "Istio Ambient - CPU (%)",
          "type": "timeseries"
        },
        {
          "datasource": "Prometheus",
          "fieldConfig": {"defaults": {"unit": "decmbytes", "min": 0}, "overrides": []},
          "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8},
          "id": 4,
          "targets": [
            {"expr": "sum(container_memory_working_set_bytes{namespace=\"perf-app\",pod=~\"istio-ambient-gw.*\",container!=\"POD\"}) / 1024 / 1024", "legendFormat": "gateway memory"},
            {"expr": "sum(container_memory_working_set_bytes{namespace=\"istio-system\",pod=~\"ztunnel.*\",container!=\"POD\"}) / 1024 / 1024", "legendFormat": "ztunnel memory"}
          ],
          "title": "Istio Ambient - Memory (MB)",
          "type": "timeseries"
        },
        {
          "datasource": "Prometheus",
          "fieldConfig": {"defaults": {"unit": "short", "min": 0}, "overrides": []},
          "gridPos": {"h": 8, "w": 12, "x": 0, "y": 16},
          "id": 5,
          "targets": [
            {"expr": "sum(istio_tcp_connections_opened_total{reporter=\"source\"})", "legendFormat": "connections opened"},
            {"expr": "sum(istio_tcp_connections_closed_total{reporter=\"source\"})", "legendFormat": "connections closed"}
          ],
          "title": "Istio Ambient - TCP Connections",
          "type": "timeseries"
        },
        {
          "datasource": "Prometheus",
          "fieldConfig": {"defaults": {"unit": "percentunit", "max": 1, "min": 0}, "overrides": []},
          "gridPos": {"h": 8, "w": 12, "x": 12, "y": 16},
          "id": 6,
          "targets": [
            {"expr": "sum(rate(istio_requests_total{response_code=~\"5..\",source_workload_namespace=\"perf-app\"}[1m])) / sum(rate(istio_requests_total{source_workload_namespace=\"perf-app\"}[1m]))", "legendFormat": "5xx error rate"}
          ],
          "title": "Istio Ambient - Error Rate (5xx)",
          "type": "stat"
        }
      ],
      "refresh": "10s",
      "schemaVersion": 38,
      "style": "dark",
      "tags": ["gateway", "istio", "ambient"],
      "templating": {"list": []},
      "time": {"from": "now-15m", "to": "now"},
      "timezone": "browser",
      "title": "Gateway - Istio Ambient",
      "uid": "gw-istio-ambient",
      "version": 1
    }
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-kong
  labels:
    grafana_dashboard: "1"
data:
  kong.json: |
    {
      "annotations": {"list": []},
      "editable": true,
      "graphTooltip": 0,
      "id": null,
      "links": [],
      "panels": [
        {
          "datasource": "Prometheus",
          "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
          "id": 1,
          "targets": [
            {"expr": "sum(rate(kong_http_requests_total[1m]))", "legendFormat": "req/s"}
          ],
          "title": "Kong - TPS (req/s)",
          "type": "timeseries"
        },
        {
          "datasource": "Prometheus",
          "fieldConfig": {"defaults": {"unit": "s", "min": 0}, "overrides": []},
          "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0},
          "id": 2,
          "targets": [
            {"expr": "histogram_quantile(0.95, sum(rate(kong_request_latency_seconds_bucket[5m])) by (le))", "legendFormat": "p95"},
            {"expr": "histogram_quantile(0.99, sum(rate(kong_request_latency_seconds_bucket[5m])) by (le))", "legendFormat": "p99"}
          ],
          "title": "Kong - Latency (p95/p99) sec",
          "type": "timeseries"
        },
        {
          "datasource": "Prometheus",
          "fieldConfig": {"defaults": {"unit": "percent", "min": 0, "max": 100}, "overrides": []},
          "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
          "id": 3,
          "targets": [
            {"expr": "sum(rate(container_cpu_usage_seconds_total{namespace=\"perf-app\",pod=~\"kong.*\",container!=\"POD\"}[5m])) * 100", "legendFormat": "cpu usage"}
          ],
          "title": "Kong Gateway - CPU (%)",
          "type": "timeseries"
        },
        {
          "datasource": "Prometheus",
          "fieldConfig": {"defaults": {"unit": "decmbytes", "min": 0}, "overrides": []},
          "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8},
          "id": 4,
          "targets": [
            {"expr": "sum(container_memory_working_set_bytes{namespace=\"perf-app\",pod=~\"kong.*\",container!=\"POD\"}) / 1024 / 1024", "legendFormat": "memory"}
          ],
          "title": "Kong Gateway - Memory (MB)",
          "type": "timeseries"
        }
      ],
      "refresh": "10s",
      "schemaVersion": 38,
      "style": "dark",
      "tags": ["gateway", "kong"],
      "templating": {"list": []},
      "time": {"from": "now-15m", "to": "now"},
      "timezone": "browser",
      "title": "Gateway - Kong",
      "uid": "gw-kong",
      "version": 1
    }
YAML

info "Installed kube-prometheus-stack in namespace ${MON_NS}"
info "Grafana: kubectl -n ${MON_NS} port-forward svc/kps-grafana 3000:80"
info "Prometheus: kubectl -n ${MON_NS} port-forward svc/kps-kube-prometheus-stack-prometheus 9090:9090"
