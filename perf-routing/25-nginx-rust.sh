#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib.sh"

need_cmd kubectl

ING_NS="ingress-nginx"

info "Installing ingress-nginx..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.3/deploy/static/provider/cloud/deploy.yaml

kubectl -n "${ING_NS}" rollout status deploy/ingress-nginx-controller --timeout=5m

info "Creating Ingress route /echo -> svc/rust-echo" 
ensure_ns "${APP_NS}"

kubectl -n "${APP_NS}" apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: rust-echo-ing
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - path: /echo
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
