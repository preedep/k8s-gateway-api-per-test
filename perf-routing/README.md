# perf-routing

## Quick start (Thai)

รันตามลำดับ:
```bash
bash perf-routing/00-prereqs.sh
bash perf-routing/15-rust-app.sh
```

เลือก deploy controller ที่ต้องการทดสอบ (เลือกอย่างใดอย่างหนึ่ง):

- NGINX Ingress:
```bash
bash perf-routing/25-nginx-rust.sh
bash perf-routing/55-loadtest-fortio-rust.sh nginx
```

- Envoy Gateway:
```bash
bash perf-routing/33-envoy-gateway-rust.sh
bash perf-routing/55-loadtest-fortio-rust.sh envoy
```

- Istio Gateway API:
```bash
bash perf-routing/43-istio-gatewayapi-rust.sh
bash perf-routing/55-loadtest-fortio-rust.sh istio
```

- Kong Gateway Operator (Gateway API):
```bash
bash perf-routing/37-kong-gateway-operator-rust.sh
bash perf-routing/55-loadtest-fortio-rust.sh kong
```

ปรับพารามิเตอร์ load test:
```bash
bash perf-routing/55-loadtest-fortio-rust.sh <mode> <duration> <concurrency> <qps>
# example
bash perf-routing/55-loadtest-fortio-rust.sh envoy 60s 128 0
```

หมายเหตุ:
- สคริปต์ backend แบบเดิม (http-echo) และชุด load test แบบเดิม ถูกย้ายไปไว้ที่ `perf-routing/_echo/` เพื่อไม่ให้สับสน

Cleanup:
```bash
bash perf-routing/90-cleanup.sh
```

## Quick start (English)

Run in order:
```bash
bash perf-routing/00-prereqs.sh
bash perf-routing/15-rust-app.sh
```

Pick one controller:

- NGINX Ingress:
```bash
bash perf-routing/25-nginx-rust.sh
bash perf-routing/55-loadtest-fortio-rust.sh nginx
```

- Envoy Gateway:
```bash
bash perf-routing/33-envoy-gateway-rust.sh
bash perf-routing/55-loadtest-fortio-rust.sh envoy
```

- Istio Gateway API:
```bash
bash perf-routing/43-istio-gatewayapi-rust.sh
bash perf-routing/55-loadtest-fortio-rust.sh istio
```

- Kong Gateway Operator (Gateway API):
```bash
bash perf-routing/37-kong-gateway-operator-rust.sh
bash perf-routing/55-loadtest-fortio-rust.sh kong
```

Tune load test:
```bash
bash perf-routing/55-loadtest-fortio-rust.sh <mode> <duration> <concurrency> <qps>
```

Note:
- Legacy http-echo scripts are moved to `perf-routing/_echo/` to avoid confusion

Cleanup:
```bash
bash perf-routing/90-cleanup.sh
```
