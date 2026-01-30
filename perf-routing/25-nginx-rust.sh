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

kubectl -n "${ING_NS}" rollout status deploy/ingress-nginx-controller --timeout=5m

info "Creating Ingress route /rust-echo -> svc/rust-echo" 
ensure_ns "${APP_NS}"

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

kubectl -n "${APP_NS}" get ingress rust-echo-ing
kubectl -n "${ING_NS}" get svc ingress-nginx-controller
info "OK"
