# Phase 2 — Traefik Ingress Controller (EKS)

> **Status:** ✅ Written *as we do it* on the EKS cluster. Reflects the exact
> commands that work.

**Goal:** Install **Traefik** in the cluster, expose it through an **AWS Network
Load Balancer (NLB)**, and verify the Traefik CRDs (`IngressRoute`, `Middleware`,
`TLSStore`, …) are installed. Argo CD and the banking app both deploy routes in
later phases — they need Traefik already running.

**Time:** ~5 minutes (provisioning the NLB is the slow step, ~2–3 min).

No AWS Load Balancer Controller is required — the in-tree cloud provider creates
the NLB from a Service annotation.

---

## What is Traefik & why we use it

**Traefik** is a cloud-native edge router. Other options exist (ingress-nginx,
the AWS Load Balancer Controller's ALB ingress), but Traefik gives us:

| Feature | Why we care |
| ------- | ----------- |
| Native **`IngressRoute` CRD** | Cleaner than stock `Ingress`; priority, regex matchers, middleware composition |
| Works with plain **`Ingress`** too | Our Helm chart's `Ingress` is picked up automatically (default IngressClass) |
| **Dynamic config reload** | Change a route → updates in <1s, no restart |
| **Free dashboard** | See all routers/services/middlewares, debug 404s without kubectl |
| **Middlewares** | CORS, basic-auth, rate-limit, strip-prefix, redirect — composable in YAML |

---

## What this phase creates

```
                        internet
                           │
                           ▼
        ┌────────────────────────────────────┐
        │   AWS Network Load Balancer (NLB)   │  (spawned by the LoadBalancer Service;
        │   DNS name: k8s-traefik-….elb.…     │   in-tree provider, no LB Controller)
        └───────────────────┬─────────────────┘
                            ▼
                    ┌──────────────┐
                    │   Traefik    │  (Deployment, namespace = traefik, 2 replicas)
                    │    pods      │
                    └──────┬───────┘
                           │  CRDs: IngressRoute, Middleware, TLSStore, ServersTransport…
                           ▼
        ┌───────────────────────────────────────────────┐
        │  banking ns · argocd ns · observability ns     │
        │  (app + Argo CD UI + Grafana — later phases)   │
        └───────────────────────────────────────────────┘
```

---

## ✅ Prerequisites

| Need | How to check |
| ---- | ------------ |
| Phase 1 done (EKS up, kubeconfig) | `kubectl get nodes` shows Ready nodes |
| Public subnets tagged for ELBs | our `vpc` module sets `kubernetes.io/role/elb=1` (needed for internet-facing NLB) |
| `helm` v3 | `helm version` |
| Internet access to Helm Hub | `helm repo add traefik https://traefik.github.io/charts && helm repo update` works |

---

## Step 1 — Install Traefik via Helm

We install into a dedicated `traefik` namespace (keeps controller workloads
separate from app workloads). The NLB is requested via Service annotations.

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update traefik

helm install traefik traefik/traefik \
  --namespace traefik --create-namespace \
  --set service.type=LoadBalancer \
  --set-string service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-type"=nlb \
  --set-string service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-scheme"=internet-facing \
  --set-string service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-cross-zone-load-balancing-enabled"=true \
  --set ingressClass.enabled=true \
  --set ingressClass.isDefaultClass=true \
  --set ingressRoute.dashboard.enabled=true \
  --set deployment.replicas=2 \
  --set 'ports.web.expose.default=true' \
  --set 'ports.web.exposedPort=80' \
  --set 'ports.websecure.expose.default=true' \
  --set 'ports.websecure.exposedPort=443' \
  --set resources.requests.cpu=100m \
  --set resources.requests.memory=128Mi \
  --set resources.limits.cpu=500m \
  --set resources.limits.memory=256Mi \
  --wait --timeout=5m
```

What each flag does:

| Flag | Why |
| ---- | --- |
| `service.type=LoadBalancer` | Provision a real cloud LB. |
| `…aws-load-balancer-type=nlb` | Make it an **NLB** (network LB) instead of the legacy Classic ELB. |
| `…aws-load-balancer-scheme=internet-facing` | Public NLB (uses the tagged public subnets). |
| `…cross-zone-load-balancing-enabled=true` | Even traffic spread across AZs. |
| `ingressClass.enabled + isDefaultClass` | Traefik claims plain `Ingress` objects; unmarked Ingresses go to Traefik. |
| `ingressRoute.dashboard.enabled=true` | Auto-create the dashboard `IngressRoute` at `/dashboard/` + `/api`. |
| `deployment.replicas=2` | Two pods across nodes → ingress survives a node drain. |
| `ports.web/websecure.expose` | Expose 80 (HTTP) and 443 (HTTPS) on the NLB. Phase 7 puts a cert on 443. |
| `resources.*` | Small but realistic (~256 MiB total). |

> 📌 **The `traefik` namespace is intentional** and referenced by later docs.
> Keep it as `traefik`.

---

## Step 2 — Verify

```bash
# Helm release
helm list -n traefik
# NAME    NAMESPACE  REVISION  STATUS    CHART           APP VERSION
# traefik traefik    1         deployed  traefik-3x.x.x  v3.x.x

# Pods
kubectl -n traefik get pods
# Expect 2 traefik-... pods Running 1/1

# Service: the NLB hostname appears after ~2-3 min once AWS provisions it
kubectl -n traefik get svc traefik
# NAME     TYPE           EXTERNAL-IP                                   PORT(S)
# traefik  LoadBalancer   k8s-traefik-…-….elb.us-east-1.amazonaws.com   80:3xxxx/TCP,443:3xxxx/TCP

# CRDs installed
kubectl get crd | grep traefik.io
# ingressroutes.traefik.io, middlewares.traefik.io, tlsstores.traefik.io,
# tlsoptions.traefik.io, serverstransports.traefik.io, …
```

Save the NLB hostname — every later doc (DNS, TLS) references it:
```bash
NLB=$(kubectl -n traefik get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Traefik NLB hostname: $NLB"
```

---

## Step 3 — Quick HTTP probe (no route yet → expect 404)

```bash
curl -sI -o /dev/null -w "%{http_code}\n" "http://${NLB}/"
# 404 — Traefik is up but no route matches. Correct for this phase; the app's
# Ingress (Phase 4, Argo-applied) and the Argo CD route add the actual routes.
```

A `404` proves the NLB → Traefik path works. `Connection refused`/`timed out`
means the NLB isn't fully provisioned yet — re-check `kubectl get svc` in ~60 s.

---

## Step 4 — Reach the Traefik dashboard

The dashboard is at `/dashboard/` + `/api` via the auto-created IngressRoute.
**Trailing slash required**:

```bash
curl -sI -o /dev/null -w "%{http_code}\n" "http://${NLB}/dashboard/"
# Expect: 200
```

Open `http://<NLB>/dashboard/` in a browser →
- **Routers** — configured `IngressRoute`s, matchers, middlewares
- **Services** — backend Services Traefik forwards to
- **Middlewares** — installed middlewares (none until later phases)

⚠️ **Production note:** lock the dashboard behind basic-auth or an IP allowlist
(or don't expose it). Fine open on a learning cluster.

---

## Step 5 — NLB hostname stability

Unlike an elastic IP, an NLB gives you a **stable DNS hostname** that does **not**
change on its own — DNS records (Phase 5) point at this hostname and keep working.

The hostname **only changes if the `traefik` Service is deleted and recreated**
(a fresh NLB is provisioned). So:

- **Don't delete/recreate the Traefik Service casually.** `helm upgrade` in place
  is fine — it keeps the same NLB.
- If you *do* recreate it (or reinstall Traefik), grab the new hostname and
  **re-point the Route 53 apex ALIAS** (Phase 5, Step 9):
  ```bash
  kubectl -n traefik get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'; echo
  ```

> We serve the platform on the **apex** `vijaygiduthuri.in`. Since GoDaddy DNS
> can't put a `CNAME`/`ALIAS` on the apex, Phase 5 delegates DNS to **Route 53**
> and uses a Route 53 **ALIAS** record that tracks this NLB automatically — no
> Elastic IPs and no AWS Load Balancer Controller needed.

---

## Step 6 — What's next

You now have a working ingress controller. Next phases add **what to route**:

- **Phase 3** — CI builds + pushes images to ECR
- **Phase 4** — Argo CD + the banking-platform Application, which applies the
  **Ingress** for the app (`/` → frontend, `/api` → gateway) and the Argo CD
  route under this same Traefik NLB
- **Phase 5** — delegate DNS to Route 53 and point the apex ALIAS at this NLB
- **Phase 7** — cert-manager + Let's Encrypt → swap `http://` for `https://`

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| ------- | ------------ | --- |
| `EXTERNAL-IP <pending>` for >5 min | NLB still provisioning, or node/role lacks ELB perms | `kubectl -n traefik describe svc traefik` events; node role needs the standard EKS worker policies (from the `iam` module). |
| A **Classic ELB** appeared, not an NLB | Missing/typo'd `aws-load-balancer-type=nlb` annotation | Fix the annotation, `helm upgrade`, delete the stray LB/Service. |
| NLB created but **internal**, not internet-facing | Public subnets not tagged `kubernetes.io/role/elb=1` | The `vpc` module sets this; confirm the tags on the public subnets. |
| `curl http://<NLB>/` → `Connection refused` | Traefik pods not Ready → NLB has no healthy targets | `kubectl -n traefik get pods`; `describe`/`logs` a failing pod. |
| `curl …/dashboard/` → 404 | Dashboard IngressRoute disabled | `helm upgrade traefik traefik/traefik -n traefik --reuse-values --set ingressRoute.dashboard.enabled=true` |
| App IngressRoutes match but 404 anyway | Traefik can't see the route's namespace | Traefik 3.x watches all namespaces by default; if restricted, set `providers.kubernetesCRD.allowCrossNamespace=true`. |
| `helm install` → `resource mapping not found` | Stale Traefik CRDs from a prior install | `kubectl get crd | grep traefik.io`; delete stale ones (⚠️ also deletes dependent IngressRoutes) on a clean cluster only. |

---

➡️ **Next:** [Phase 3 — GitHub Actions CI](03-github-actions-cicd.md)
