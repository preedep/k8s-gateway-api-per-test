# perf-routing

## Quick start (Thai)

รันตามลำดับ:
```bash
bash perf-routing/00-prereqs.sh
bash perf-routing/10-app.sh
```

เลือก deploy controller ที่ต้องการทดสอบ (เลือกอย่างใดอย่างหนึ่ง):

- NGINX Ingress:
```bash
bash perf-routing/20-nginx.sh
bash perf-routing/50-loadtest-fortio.sh nginx
```

- Envoy Gateway:
```bash
bash perf-routing/30-envoy-gateway.sh
bash perf-routing/50-loadtest-fortio.sh envoy
```

- Istio Gateway API:
```bash
bash perf-routing/40-istio-gatewayapi.sh
bash perf-routing/50-loadtest-fortio.sh istio
```

- Kong Gateway Operator (Gateway API):
```bash
bash perf-routing/35-kong-gateway-operator.sh
bash perf-routing/50-loadtest-fortio.sh kong
```

ปรับพารามิเตอร์ load test:
```bash
bash perf-routing/50-loadtest-fortio.sh <mode> <duration> <concurrency> <qps>
# example
bash perf-routing/50-loadtest-fortio.sh envoy 60s 128 0
```

Cleanup:
```bash
bash perf-routing/90-cleanup.sh
```

## Quick start (English)

Run in order:
```bash
bash perf-routing/00-prereqs.sh
bash perf-routing/10-app.sh
```

Pick one controller:

- NGINX Ingress:
```bash
bash perf-routing/20-nginx.sh
bash perf-routing/50-loadtest-fortio.sh nginx
```

- Envoy Gateway:
```bash
bash perf-routing/30-envoy-gateway.sh
bash perf-routing/50-loadtest-fortio.sh envoy
```

- Istio Gateway API:
```bash
bash perf-routing/40-istio-gatewayapi.sh
bash perf-routing/50-loadtest-fortio.sh istio
```

- Kong Gateway Operator (Gateway API):
```bash
bash perf-routing/35-kong-gateway-operator.sh
bash perf-routing/50-loadtest-fortio.sh kong
```

Tune load test:
```bash
bash perf-routing/50-loadtest-fortio.sh <mode> <duration> <concurrency> <qps>
```

Cleanup:
```bash
bash perf-routing/90-cleanup.sh
```
