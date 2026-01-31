#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib.sh"

need_cmd kubectl

ensure_ns "${APP_NS}"

# Build and deploy Rust echo service
info "Building Rust echo service..."
cd "${SCRIPT_DIR}/../rust-echo-service"

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    error "Docker is not running. Please start Docker Desktop."
fi

# Build the Docker image
docker build -t rust-echo-service:latest .

# Load the image into Docker Desktop Kubernetes
docker save rust-echo-service:latest | docker load

cd "${SCRIPT_DIR}"

kubectl -n "${APP_NS}" apply -f - <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rust-echo
spec:
  replicas: 10
  selector:
    matchLabels:
      app: rust-echo
  template:
    metadata:
      labels:
        app: rust-echo
    spec:
      containers:
      - name: rust-echo
        image: rust-echo-service:latest
        imagePullPolicy: Never
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: "50m"
            memory: "64Mi"
          limits:
            cpu: "500m"
            memory: "500Mi"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 1
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: rust-echo
spec:
  selector:
    app: rust-echo
  ports:
  - name: http
    port: 80
    targetPort: 8080
YAML

wait_deploy "${APP_NS}" rust-echo
kubectl -n "${APP_NS}" get pods,svc

# Test the service
info "Testing Rust echo service..."
kubectl -n "${APP_NS}" run curl-test --image=curlimages/curl:latest --rm -i --restart=Never -- curl -s http://rust-echo/echo

info "Rust echo service deployed successfully!"
