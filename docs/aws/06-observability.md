# Phase 6 — Observability (EKS)

> **Status:** ✅ Written *as we do it* on the EKS cluster. Reflects the exact
> commands and values files that work.

**Goal:** Deploy the full metrics / logs / traces stack —
**Prometheus, Alertmanager, Grafana, Loki, Promtail, Tempo, OpenTelemetry
Collector** — into an `observability` namespace, wire the banking services'
telemetry into it, and confirm **metrics ↔ logs ↔ traces correlation** in
Grafana (click a `trace_id` in a log line → jump to the trace).

**Time:** ~15 minutes (chart installs + waiting for PVCs to bind).

Full design notes: [docs/observability.md](../observability.md).
Manifests & values: [deploy/observability/](../../deploy/observability/).

---

## Why this stack

We use the **Grafana LGTM-style** stack (Loki, Grafana, Tempo, Prometheus)
plus the **OpenTelemetry Collector** as the single OTLP ingest point:

| Concern | Tool | Why |
| ------- | ---- | --- |
| **Metrics** | Prometheus + Alertmanager | de-facto standard; the Operator turns a `ServiceMonitor` CRD into scrape config, no reloads |
| **Dashboards / alerts UI** | Grafana | one pane for all three signals; datasource-linked correlation |
| **Logs** | Loki + Promtail | Promtail ships every pod's stdout; Loki indexes by label, cheap to run in-cluster |
| **Traces** | Tempo | trace store queried straight from Grafana |
| **Ingest** | OTel Collector | services speak OTLP once → collector fans out (traces→Tempo, metrics→Prometheus) |

Everything runs **in-cluster** (no managed AWS observability services), matching
the rest of the platform's "own your data plane" design.

---

## What this phase creates

```
   banking services (OTLP :4317)          Prometheus scrapes /metrics
            │                                        ▲
            ▼                                        │  (ServiceMonitor)
   ┌──────────────────┐    traces     ┌─────────────┴──────────────┐
   │  OTel Collector  │ ───────────►  │   observability namespace   │
   │  (OTLP receiver) │    metrics    │  Prometheus + Alertmanager  │
   └──────────────────┘ ───────────►  │  Grafana · Loki · Tempo     │
                                       │  Promtail (DaemonSet)       │
   pod stdout ──Promtail──► Loki ─────►│                             │
                                       └─────────────┬──────────────┘
                                                     ▼
                                             Grafana dashboards
                                      (metrics ↔ logs ↔ traces linked)
```

---

## ✅ Prerequisites

| Need | How to check |
| ---- | ------------ |
| Phase 1 done (EKS up) | `kubectl get nodes` → Ready |
| **EBS CSI + default `gp3` StorageClass** | `kubectl get sc` shows `gp3 (default)` — Prometheus/Loki/Tempo need PVCs |
| `helm` v3 | `helm version` |
| Internet access to Helm Hub | repo adds below succeed |

> ⚠️ If `gp3` isn't the default StorageClass, the stateful pods sit `Pending`
> forever. Do **Phase 1 Step 4** (EBS CSI addon + default `gp3`) first.

---

## What gets installed (namespace `observability`)

| Component | Chart | Role |
|-----------|-------|------|
| Prometheus + Alertmanager + Grafana + node/kube exporters | `prometheus-community/kube-prometheus-stack` | metrics + dashboards + alerts (installs the Prometheus Operator CRDs) |
| Loki + Promtail | `grafana/loki-stack` | logs (pod stdout → Loki) |
| Tempo | `grafana/tempo` | traces store |
| OTel Collector | `open-telemetry/opentelemetry-collector` | receives OTLP from services → Tempo + Prometheus |

Plus a **ServiceMonitor** scraping every `part-of=banking-platform` service's
`/metrics`, and a custom **Banking Platform — Services** dashboard (loaded from a
ConfigMap Grafana auto-discovers).

---

## Step 1 — Install

Two ways. Pick one.

### A) One-shot script (fastest, what we use)

```bash
deploy/observability/install.sh
```

It creates the namespace, adds the Helm repos, and installs the four charts with
our values files, then applies the ServiceMonitor + dashboard. Under the hood it
runs exactly these (run them by hand if you want to go step by step):

```bash
kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

# metrics + Grafana + Alertmanager (also installs the Prometheus Operator CRDs)
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n observability -f deploy/observability/values/kube-prometheus-stack.yaml --wait --timeout 10m

# traces
helm upgrade --install tempo grafana/tempo \
  -n observability -f deploy/observability/values/tempo.yaml --wait --timeout 5m

# logs — release name MUST be "loki-stack" (Grafana's Loki datasource URL points
# at the loki-stack Service; a different release name → 502 / no logs in Grafana)
helm upgrade --install loki-stack grafana/loki-stack \
  -n observability -f deploy/observability/values/loki-stack.yaml --wait --timeout 5m

# OTLP ingest
helm upgrade --install otel-collector open-telemetry/opentelemetry-collector \
  -n observability -f deploy/observability/values/otel-collector.yaml --wait --timeout 5m

# our ServiceMonitor + dashboards (servicemonitor + both dashboard ConfigMaps)
kubectl apply -f deploy/observability/manifests/
```

> 📌 Install **kube-prometheus-stack first** — it brings the Prometheus Operator
> CRDs (`ServiceMonitor`, etc.); our `servicemonitor.yaml` fails to apply without
> them.

### B) GitOps (managed by Argo CD — recommended once Phase 4 is done)

Let Argo CD own the stack so it self-heals. You don't apply these individually —
the **app-of-apps** root (Phase 4 / [deploy/argocd/](../../deploy/argocd/))
already creates the observability Applications from
[deploy/argocd/apps/observability/](../../deploy/argocd/apps/observability/):
`kube-prometheus-stack`, `loki-stack`, `tempo`, `otel-collector`, and
`observability-extras` (the ServiceMonitor + dashboards). Each pulls its chart
from the Helm repo and its values from `deploy/observability/values/*.yaml` — the
**same files** this script uses. So on a real cluster, bootstrapping Argo CD
installs observability too; the script below is the non-GitOps fallback.

---

## Step 2 — Confirm pods & PVCs are healthy

```bash
kubectl -n observability get pods
# All Running: kube-prometheus-stack-* (prometheus, alertmanager, grafana,
# operator, node-exporter DaemonSet, kube-state-metrics), tempo-0, loki-0,
# loki-promtail-* (DaemonSet), otel-collector-*

kubectl -n observability get pvc
# prometheus-…, storage-tempo-0, storage-loki-0 → all Bound (on gp3)
```

If anything is `Pending`, jump to Troubleshooting (almost always the `gp3` PVC issue).

---

## Step 3 — Point the platform at the collector

The Helm `values.yaml` already sets, for **every** service:

```yaml
otel:
  enabled: "true"
  endpoint: "otel-collector.observability.svc.cluster.local:4317"
  insecure: "true"
```

So each service exports **traces** (and OTLP metrics) to the collector, while
Prometheus **also** scrapes `/metrics` directly (belt-and-suspenders — RED
metrics come through scrape, spans through OTLP).

If you flipped OTEL on *after* the app was already running, restart to pick it up:

```bash
kubectl rollout restart deploy -n banking
```

---

## Step 4 — Verify the three signals

Generate a little traffic through the gateway first (register → deposit, etc.),
then check each signal:

```bash
# ── Metrics — Prometheus targets up ──────────────────────────────
kubectl -n observability port-forward svc/kube-prometheus-stack-prometheus 9090:9090 &
curl -s 'http://localhost:9090/api/v1/query?query=count(up{namespace="banking"}==1)' \
  | grep -o '"value":\[[^]]*\]'
# → non-zero count (one target per banking pod)

# ── Traces — Tempo has recent traces ─────────────────────────────
kubectl -n observability port-forward svc/tempo 3200:3200 &
curl -s "http://localhost:3200/api/search?q=%7B%7D&limit=3&start=$(date -d '15 min ago' +%s)&end=$(date +%s)" | head -c 200
# → a JSON "traces":[…] array

# ── Logs — Loki has banking logs carrying trace_id ───────────────
kubectl -n observability port-forward svc/loki 3100:3100 &
S=$(date -d '15 min ago' +%s)000000000; E=$(date +%s)000000000
curl -s -G http://localhost:3100/loki/api/v1/query_range \
  --data-urlencode 'query={namespace="banking"}' \
  --data-urlencode "start=$S" --data-urlencode "end=$E" --data-urlencode 'limit=5' \
  | grep -o '"status":"[^"]*"'
# → "status":"success"  (log lines contain trace_id)
```

Expected: a non-zero `up` count, a `traces` array from Tempo, and
`"status":"success"` (lines carrying `trace_id`) from Loki.

---

## Step 5 — Access Grafana

**Via Traefik (recommended, after Phase 7):** `https://vijaygiduthuri.in/grafana`
— Phase 7 sets `serve_from_sub_path` + the IngressRoute so Grafana serves under
the `/grafana` sub-path on the single app host.

**Port-forward (any time, no ingress needed):**
```bash
kubectl -n observability port-forward svc/kube-prometheus-stack-grafana 3000:80
# http://localhost:3000   (admin / admin — see note below)
```

> 🔑 Login is `admin` / **`admin`** (our `grafana.adminPassword: admin` in
> `values/kube-prometheus-stack.yaml`). Change it for anything real.
>
> ⚠️ **Grafana here has no PVC (ephemeral).** Its SQLite DB lives on `emptyDir`,
> so **anything changed in the UI — the admin password, hand-built dashboards —
> is lost when the pod restarts** and reverts to the provisioned values. That's
> why all dashboards are provisioned **as code** (ConfigMaps labeled
> `grafana_dashboard`), which *do* survive restarts. Want durable UI state? Add a
> PVC via `grafana.persistence` in the values.

Explore:
- **Banking — Service Detail (per service)** dashboard — pick a service from the
  `Service` dropdown to see its **running pods, request rate by status, p50/p95/p99
  latency, CPU, memory, and live Loki logs**, all filtered to that one service.
  (Provisioned from `deploy/observability/manifests/service-detail-dashboard.yaml`.)
- **Banking Platform — Services** dashboard (fleet-wide request rate, p95, 5xx).
- Bundled **Kubernetes / Nodes / Pods** dashboards.
- **Explore → Loki**: click a log line's `trace_id` → it jumps to the trace in
  **Tempo** (log↔trace correlation); from a Tempo span, jump back to its logs.

---

## Step 6 — Exposing Grafana / Prometheus / Alertmanager (sub-paths)

HTTPS routes for `/grafana`, `/prometheus`, `/alertmanager` under
`vijaygiduthuri.in` — plus the sub-path serving config each app needs
(`serve_from_sub_path`, `routePrefix`) — are configured in **Phase 7**
(Traefik IngressRoutes + TLS), so everything lives on the single app host.

> ⚠️ **Prometheus** and **Alertmanager** have **no login** of their own. On this
> learning cluster we expose them openly; for anything real, put a Traefik
> basic-auth/IP-allowlist middleware in front or keep them port-forward-only.

---

## Step 7 — metrics-server (required for HPA autoscaling)

The chart deploys **HPAs** for every service, but they need the Kubernetes
**resource-metrics API** (CPU/memory) — which **EKS does not ship**. Without
metrics-server, HPAs show `cpu: <unknown>/70%` and never scale, and
`kubectl top` fails.

**GitOps (default):** it's an Argo CD app
([deploy/argocd/apps/metrics-server.yaml](../../deploy/argocd/apps/metrics-server.yaml)),
so it installs automatically when you bootstrap Argo CD (Phase 4). Nothing to do.

**Manual (non-GitOps) alternative:**
```bash
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm upgrade --install metrics-server metrics-server/metrics-server \
  -n kube-system --set 'args={--kubelet-insecure-tls}' --wait
```
> `--kubelet-insecure-tls` is **required on EKS** — the kubelet's serving cert
> isn't verifiable by metrics-server by default, so without it the pod stays
> `Running` but the metrics API returns errors.

**Verify:**
```bash
kubectl top nodes                    # shows CPU/MEM per node
kubectl -n banking get hpa           # TARGETS show real % (e.g. cpu: 4%/70%), not <unknown>
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| ------- | ------------ | --- |
| Prometheus/Loki/Tempo pods `Pending` | No `gp3`/EBS CSI → PVCs unbound | Do **Phase 1 Step 4** (EBS CSI addon + default `gp3` SC), then delete the Pending pods so they reschedule. |
| `servicemonitor.yaml` → `no matches for kind "ServiceMonitor"` | Applied before kube-prometheus-stack | Install kube-prometheus-stack first (it brings the Operator CRDs), then re-apply. |
| `up{namespace="banking"}` empty | ServiceMonitor not matching | Confirm services keep label `app.kubernetes.io/part-of: banking-platform` and a port named `http`; `serviceMonitorSelectorNilUsesHelmValues=false` is set in values. |
| No traces in Tempo | OTEL disabled or wrong endpoint | Check `OTEL_ENABLED=true` and endpoint `otel-collector.observability.svc.cluster.local:4317`; `kubectl logs` the collector for OTLP receive errors. |
| Loki empty | Promtail not shipping | `kubectl get pods -n observability` (promtail DaemonSet, one per node); check its logs for scrape/permission errors. |
| **Grafana logs panel empty / Loki datasource 502** | Grafana's Loki datasource URL doesn't match the Loki **Service name**. The `loki-stack` chart's Service is named after the release → **must be `loki-stack`** (`http://loki-stack.observability.svc.cluster.local:3100`). Install the chart with release name `loki-stack`. | Confirm `kubectl -n observability get svc \| grep loki` shows `loki-stack`; the datasource URL in `values/kube-prometheus-stack.yaml` matches it. |
| Log stream filter: which label? | Promtail labels logs with `namespace`, `app` (=service name), `pod`, `container` | Filter by service with `{namespace="banking", app="<service>"}`. |
| Grafana Tempo datasource errors | Wrong port | Datasource URL must be `http://tempo:3200` (Tempo HTTP), **not** 3100 (that's Loki). |
| Grafana login fails | Creds | `admin` / `admin` (our `grafana.adminPassword`). Note UI password changes reset on pod restart (ephemeral Grafana — no PVC). |

---

➡️ **Next:** [Phase 7 — HTTPS / TLS](07-https-tls.md)
