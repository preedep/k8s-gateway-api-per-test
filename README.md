# Kubernetes Routing Performance Test (Docker Desktop)

## ภาษาไทย

เอกสาร/สคริปต์ชุดนี้ใช้สำหรับทำ **performance test ด้าน HTTP routing** บนเครื่องตัวเอง (Docker Desktop Kubernetes) โดยสลับทดสอบได้ 4 แบบ:

- **NGINX Ingress Controller** (Ingress legacy)
- **Envoy Gateway** (Gateway API)
- **Istio (Gateway API mode)** ใช้เป็น Gateway เท่านั้น (ไม่ต้องทำ service mesh / ไม่บังคับ sidecar)
- **Kong Gateway Operator** (Gateway API)

โครงสร้างไฟล์อยู่ในโฟลเดอร์ `perf-routing/` ใน root ของ repo นี้

### Prerequisites
- Docker Desktop 4.58.1 (หรือใกล้เคียง)
- Enable Kubernetes ใน Docker Desktop
- `kubectl` ใช้งานได้และชี้ไปที่ Docker Desktop context

### Enable Kubernetes (Docker Desktop)
1. Docker Desktop -> Settings
2. Kubernetes -> ติ๊ก **Enable Kubernetes**
3. Apply & Restart
4. รอจน Kubernetes ขึ้น Running

ตรวจสอบ:
```bash
kubectl get nodes
```

### แนวคิดเพื่อให้เทียบผลได้แฟร์
- ใช้แอปเดียวกัน (`echo` service) เป็น backend
- ใช้ rule แบบเดียวกัน: path `/echo`
- ยิงโหลดจากในคลัสเตอร์ (Fortio pod) เพื่อลด noise จาก network ของ macOS

### วิธีใช้งาน (แนะนำให้รันตามลำดับ)
ติดตั้ง Gateway API CRDs + deploy แอปทดสอบ:
```bash
bash perf-routing/00-prereqs.sh
```

**เลือกแอปทดสอบ:**

แอปเดิม (http-echo):
```bash
bash perf-routing/10-app.sh
```

**หรือแอปใหม่ Rust microservice:**
```bash
bash perf-routing/15-rust-app.sh
```

จากนั้นเลือกติดตั้ง/ทดสอบ 1 ตัว (เลือกอย่างใดอย่างหนึ่ง):

NGINX Ingress:
```bash
# สำหรับแอปเดิม
bash perf-routing/20-nginx.sh
bash perf-routing/50-loadtest-fortio.sh nginx

# สำหรับ Rust microservice
bash perf-routing/25-nginx-rust.sh
bash perf-routing/55-loadtest-fortio-rust.sh nginx
```

Envoy Gateway:
```bash
# สำหรับแอปเดิม
bash perf-routing/30-envoy-gateway.sh
bash perf-routing/50-loadtest-fortio.sh envoy

# สำหรับ Rust microservice
bash perf-routing/33-envoy-gateway-rust.sh
bash perf-routing/55-loadtest-fortio-rust.sh envoy
```

Istio (Gateway API mode):
```bash
# สำหรับแอปเดิม
bash perf-routing/40-istio-gatewayapi.sh
bash perf-routing/50-loadtest-fortio.sh istio

# สำหรับ Rust microservice
bash perf-routing/43-istio-gatewayapi-rust.sh
bash perf-routing/55-loadtest-fortio-rust.sh istio
```

Kong Gateway Operator (Gateway API):
```bash
# สำหรับแอปเดิม
bash perf-routing/35-kong-gateway-operator.sh
bash perf-routing/50-loadtest-fortio.sh kong

# สำหรับ Rust microservice
bash perf-routing/37-kong-gateway-operator-rust.sh
bash perf-routing/55-loadtest-fortio-rust.sh kong
```


### Cleanup
ลบทุกอย่างที่สร้างจากสคริปต์:
```bash
bash perf-routing/90-cleanup.sh
```

หมายเหตุ:
- สคริปต์ Istio ต้องมี `istioctl` ในเครื่องก่อน (สคริปต์จะแจ้งวิธีติดตั้งหากไม่มี)
- ถ้าต้องการปรับจำนวน request/เวลา/concurrency ให้ดูตัวแปรใน `perf-routing/50-loadtest-fortio.sh`

---

## English

This repository contains a small, repeatable setup to run **HTTP routing performance tests** on your local machine using **Docker Desktop Kubernetes**, comparing:

- **NGINX Ingress Controller** (Ingress legacy)
- **Envoy Gateway** (Gateway API)
- **Istio in Gateway API mode** (gateway only; no mesh config required, no sidecar injection enforced)
- **Kong Gateway Operator** (Gateway API)

All scripts live under `perf-routing/`.

### Prerequisites
- Docker Desktop 4.58.1 (or similar)
- Kubernetes enabled in Docker Desktop
- `kubectl` configured for the Docker Desktop cluster

### Enable Kubernetes (Docker Desktop)
1. Docker Desktop -> Settings
2. Kubernetes -> check **Enable Kubernetes**
3. Apply & Restart
4. Wait until Kubernetes is Running

Verify:
```bash
kubectl get nodes
```

### Fair comparison guidelines
- Same backend app (`echo`)
- Same routing rule: `/echo`
- Run load tests from inside the cluster (Fortio pod) to reduce host networking noise on macOS

### Usage (run in order)
Install Gateway API CRDs + deploy the test app:
```bash
bash perf-routing/00-prereqs.sh
```

**Choose test app:**

Original app (http-echo):
```bash
bash perf-routing/10-app.sh
```

**Or new Rust microservice:**
```bash
bash perf-routing/15-rust-app.sh
```

Pick ONE controller to install/test:

NGINX Ingress:
```bash
# For original app
bash perf-routing/20-nginx.sh
bash perf-routing/50-loadtest-fortio.sh nginx

# For Rust microservice
bash perf-routing/25-nginx-rust.sh
bash perf-routing/55-loadtest-fortio-rust.sh nginx
```

Envoy Gateway:
```bash
# For original app
bash perf-routing/30-envoy-gateway.sh
bash perf-routing/50-loadtest-fortio.sh envoy

# For Rust microservice
bash perf-routing/33-envoy-gateway-rust.sh
bash perf-routing/55-loadtest-fortio-rust.sh envoy
```

Istio (Gateway API mode):
```bash
# For original app
bash perf-routing/40-istio-gatewayapi.sh
bash perf-routing/50-loadtest-fortio.sh istio

# For Rust microservice
bash perf-routing/43-istio-gatewayapi-rust.sh
bash perf-routing/55-loadtest-fortio-rust.sh istio
```

Kong Gateway Operator (Gateway API):
```bash
# For original app
bash perf-routing/35-kong-gateway-operator.sh
bash perf-routing/50-loadtest-fortio.sh kong

# For Rust microservice
bash perf-routing/37-kong-gateway-operator-rust.sh
bash perf-routing/55-loadtest-fortio-rust.sh kong
```

### Cleanup
Remove everything created by these scripts:
```bash
bash perf-routing/90-cleanup.sh
```

Notes:
- The Istio script requires `istioctl` to be installed locally (the script will print install hints if missing).
- Tuning (duration/concurrency/QPS) is in `perf-routing/50-loadtest-fortio.sh`.
