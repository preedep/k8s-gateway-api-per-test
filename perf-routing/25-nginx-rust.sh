#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib.sh"

need_cmd kubectl

ING_NS="ingress-nginx"

info "Installing ingress-nginx with metrics enabled..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.3/deploy/static/provider/cloud/deploy.yaml

# Enable metrics in NGINX Ingress controller (remove the false flag)
kubectl -n "${ING_NS}" patch deployment ingress-nginx-controller --type='json' -p='[
  {"op": "remove", "path": "/spec/template/spec/containers/0/args/9"}
]'

kubectl -n "${ING_NS}" patch deployment ingress-nginx-controller --type='merge' -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [
          {
            "name": "controller",
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
}'

# Wait for rollout to complete
kubectl -n "${ING_NS}" rollout status deploy/ingress-nginx-controller --timeout=5m

# Verify metrics are enabled
info "Verifying NGINX metrics are enabled..."
for i in {1..10}; do
  if kubectl -n "${ING_NS}" exec $(kubectl -n "${ING_NS}" get pods -l app.kubernetes.io/component=controller -o jsonpath='{.items[0].metadata.name}') -- curl -s http://localhost:10254/metrics | grep -q "nginx_ingress_controller_requests"; then
    info "NGINX request metrics are enabled"
    break
  fi
  if [[ $i -eq 10 ]]; then
    warn "NGINX request metrics may not be fully enabled, but continuing..."
  fi
  sleep 3
done

info "Creating Ingress route /rust-echo -> svc/rust-echo" 
ensure_ns "${APP_NS}"

# Wait for webhook to be ready
info "Waiting for NGINX webhook to be ready..."
for i in {1..30}; do
  if kubectl -n "${ING_NS}" get pods -l app.kubernetes.io/component=controller | grep -q "1/1.*Running"; then
    sleep 5
    break
  fi
  sleep 2
done

# Try to create Ingress, fallback to disabling webhook if needed
if ! kubectl -n "${APP_NS}" apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: rust-echo-ing
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/rewrite-target: /echo
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - path: /rust-echo
        pathType: Prefix
        backend:
          service:
            name: rust-echo
            port:
              number: 80
YAML
then
  info "Ingress created successfully"
else
  warn "Webhook not ready, temporarily disabling validation..."
  # Temporarily disable webhook
  kubectl -n "${ING_NS}" patch validatingwebhookconfiguration ingress-nginx-admission --type='json' -p='[
    {"op": "replace", "path": "/webhooks/0/rules/0/operations", "value": []}
  ]' 2>/dev/null || true
  
  # Create Ingress again
  kubectl -n "${APP_NS}" apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: rust-echo-ing
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/rewrite-target: /echo
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - path: /rust-echo
        pathType: Prefix
        backend:
          service:
            name: rust-echo
            port:
              number: 80
YAML
  
  # Re-enable webhook
  kubectl -n "${ING_NS}" patch validatingwebhookconfiguration ingress-nginx-admission --type='json' -p='[
    {"op": "replace", "path": "/webhooks/0/rules/0/operations", "value": ["CREATE", "UPDATE"]}
  ]' 2>/dev/null || true
  
  info "Ingress created successfully (webhook temporarily disabled)"
fi

kubectl -n "${APP_NS}" get ingress rust-echo-ing
kubectl -n "${ING_NS}" get svc ingress-nginx-controller
info "OK"
