#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib.sh"

need_cmd kubectl

MON_NS="perf-monitoring"

info "Starting port forwarding for monitoring stack..."

# Function to handle cleanup
cleanup() {
    info "Stopping all port forwards..."
    jobs -p | xargs -r kill
    exit 0
}

# Set up signal handlers
trap cleanup SIGINT SIGTERM

# Start Grafana port-forward
info "Starting Grafana port-forward on http://localhost:3000"
kubectl -n "${MON_NS}" port-forward svc/kps-grafana 3000:80 &
GRAFANA_PID=$!

# Start Prometheus port-forward  
info "Starting Prometheus port-forward on http://localhost:9090"
kubectl -n "${MON_NS}" port-forward svc/kps-kube-prometheus-stack-prometheus 9090:9090 &
PROMETHEUS_PID=$!

# Wait a moment for port-forwards to start
sleep 3

# Check if port-forwards are working
if curl -s http://localhost:3000/api/health > /dev/null 2>&1; then
    success "Grafana is accessible at http://localhost:3000"
    success "Login: admin / admin"
else
    warn "Grafana may not be ready yet, check http://localhost:3000"
fi

if curl -s http://localhost:9090/-/healthy > /dev/null 2>&1; then
    success "Prometheus is accessible at http://localhost:9090"
else
    warn "Prometheus may not be ready yet, check http://localhost:9090"
fi

info ""
info "Port forwarding is running. Press Ctrl+C to stop."
info ""
info "Access URLs:"
info "  Grafana:    http://localhost:3000 (admin/admin)"
info "  Prometheus: http://localhost:9090"
info ""

# Wait for all background jobs
wait
