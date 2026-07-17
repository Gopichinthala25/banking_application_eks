# End-to-End Deployment Runbook (dev on EKS)

Tight, ordered command sequence to bring the whole platform up on AWS EKS and
run an end-to-end test. Detailed explanations live in `01`–`07`; this is the
"just run it" checklist. **Budget ~half a day** for a first run.

Legend: 🤖 = run the command · 🙋 = **manual step only you can do** ·
⏳ = long wait · ∥ = can run in parallel with the previous block.

Fixed values for this project:
```
ACCOUNT   118178010323          REGION   us-east-1        CLUSTER  banking-dev
DOMAIN    vijaygiduthuri.in     ECR      118178010323.dkr.ecr.us-east-1.amazonaws.com/banking-platform
STATE S3  banking-platform-tfstate-118178010323
```

---

## Pre-flight (once)
```bash
aws sts get-caller-identity     # creds present, account 118178010323
terraform version               # >= 1.10
kubectl version --client ; helm version
```
🙋 **CI secrets** — GitHub repo → Settings → Secrets and variables → Actions:
| Kind | Name | Value |
|------|------|-------|
| Secret | `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | your keys |
| Variable | `AWS_REGION` | `us-east-1` |
| Variable | `ECR_REGISTRY` | `118178010323.dkr.ecr.us-east-1.amazonaws.com` |
| Variable | `ECR_REPOSITORY` | `banking-platform` |

> ⚠️ **This laptop quirk:** `terraform/environments/dev/.terraform` is root-owned
> from an old run. Either remove it (`sudo rm -rf terraform/environments/dev/.terraform`)
> or export a writable data dir before every terraform command:
> `export TF_DATA_DIR=$HOME/.tf-dev` (use the SAME value for init/plan/apply/destroy).

---

## 1 — Infra (Terraform)  ⏳ ~20 min
```bash
# state bucket (already created; skip if it exists)
aws s3api create-bucket --bucket banking-platform-tfstate-118178010323 --region us-east-1 || true
aws s3api put-bucket-versioning --bucket banking-platform-tfstate-118178010323 \
  --versioning-configuration Status=Enabled

cd terraform/environments/dev
terraform init                       # real S3 backend (bucket matches backend.tf now)
terraform apply                      # REAL sizing: t3.xlarge x4  (~20 min, billable)
terraform output                     # note route53_name_servers, ecr_repository_url
```

## 2 — kubeconfig + Traefik  ~5 min
```bash
aws eks update-kubeconfig --name banking-dev --region us-east-1
kubectl get nodes                    # 4x t3.xlarge Ready

helm repo add traefik https://traefik.github.io/charts && helm repo update traefik
helm install traefik traefik/traefik -n traefik --create-namespace \
  --set service.type=LoadBalancer \
  --set-string service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-type"=nlb \
  --set-string service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-scheme"=internet-facing \
  --set ingressClass.enabled=true --set ingressClass.isDefaultClass=true \
  --wait --timeout=5m
NLB=$(kubectl -n traefik get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'); echo "$NLB"
```
> Full flags + rationale: `02-traefik-ingress.md`.

## 3 — Images → ECR (CI)  ∥ can start during step 2  ⏳ ~15–25 min
🙋 GitHub → **Actions → "CI (AWS / ECR)" → Run workflow** (uses the secrets above).
It builds+scans+pushes all 32 images and **auto-bumps `values.yaml` image tags**,
committing to `main`. Wait for it to go green **before** step 4b.
```bash
aws ecr list-images --repository-name banking-platform --region us-east-1 \
  --query 'imageIds[].imageTag' --output table | head
```
> Details: `03-github-actions-cicd.md`.

## 4 — Argo CD + GitOps bootstrap  ~5 min setup + ⏳ ~20 min sync
```bash
helm repo add argo https://argoproj.github.io/argo-helm && helm repo update argo
helm install argocd argo/argo-cd -n argocd --create-namespace \
  --set server.service.type=ClusterIP \
  --set 'configs.params.server\.insecure=true' \
  --set 'configs.params.server\.rootpath=/argocd' --wait --timeout=5m

# Argo CD route on the same NLB
kubectl apply -f - <<'EOF'
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata: { name: argocd, namespace: argocd }
spec:
  entryPoints: [web]
  routes:
    - match: PathPrefix(`/argocd`)
      kind: Rule
      services: [{ name: argocd-server, port: 80 }]
EOF
```
🙋 **repo access (PAT)** — create the repository Secret (classic PAT, `repo` scope):
```bash
GH_PAT='ghp_xxxxxxxxxxxxxxxxxxxx'
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: banking-repo
  namespace: argocd
  labels: { argocd.argoproj.io/secret-type: repository }
stringData:
  type: git
  url: https://github.com/vijaygiduthuri/banking_application_eks.git
  username: vijaygiduthuri
  password: ${GH_PAT}
EOF
```
**4b — bootstrap (after step 3 is green):**
```bash
kubectl apply -f deploy/argocd/bootstrap/project.yaml
kubectl apply -f deploy/argocd/bootstrap/root-app.yaml
watch kubectl -n argocd get applications      # all -> Synced / Healthy
kubectl -n banking get pods                   # ~35 pods Running (Postgres/Kafka init first)
```
> Details: `04-argocd.md`. Admin password:
> `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo`

## 5 — E2E test over the NLB (HTTP) — validate the app WITHOUT waiting on DNS
```bash
NLB=$(kubectl -n traefik get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
H="Host: vijaygiduthuri.in"
# register -> capture token -> deposit -> balance
TOKEN=$(curl -s -X POST "http://$NLB/api/v1/auth/register" -H "$H" \
  -d '{"email":"e2e@bank.io","password":"password123"}' | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')
echo "token len: ${#TOKEN}"
curl -s "http://$NLB/api/v1/fx/rates" -H "$H" | head -c 200; echo
# open the app UI in a browser via the NLB (send Host header) or wait for DNS (step 6)
```
Also check observability: `kubectl -n observability get pods` and port-forward Grafana
(`kubectl -n observability port-forward svc/kube-prometheus-stack-grafana 3000:80`).

> ✅ If register→deposit→balance works here, **the platform is validated.** DNS +
> HTTPS below are polish and can be done anytime.

## 6 — DNS (apex via Route 53)  🙋 GoDaddy step + ⏳ propagation
```bash
cd terraform/environments/dev
terraform apply -var 'create_apex_record=true'   # apex ALIAS -> Traefik NLB
terraform output route53_name_servers            # the 4 NS to delegate
```
🙋 **GoDaddy** → your domain → **Nameservers → Change → enter your own** → paste the
4 Route 53 nameservers → Save. ⏳ Propagation: minutes to a few hours.
```bash
dig +short NS vijaygiduthuri.in     # should show ns-….awsdns-…
dig +short vijaygiduthuri.in        # should show the NLB IPs
```
> Details: `05-dns-godaddy.md`.

## 7 — HTTPS / TLS  ~2–5 min after DNS resolves
cert-manager + the `letsencrypt-prod` ClusterIssuer are already synced by Argo.
Flip the app to HTTPS via GitOps:
```bash
# set ingress.tls: true in deploy/helm/banking-platform/values.yaml, then:
git add deploy/helm/banking-platform/values.yaml
git commit -m "phase 7: enable TLS"     # (identity: Vijay Giduthuri)
git push origin main
kubectl -n banking get certificate      # banking-tls -> READY=True (~1-3 min)
```
Also copy `banking-tls` to argocd/observability + add `websecure` IngressRoutes
per `07-https-tls.md` for `/argocd`, `/grafana`, etc.

## 8 — Final check
```
https://vijaygiduthuri.in            🏦 app
https://vijaygiduthuri.in/argocd     🚀 Argo CD
https://vijaygiduthuri.in/grafana    📊 Grafana
```

---

## Teardown (stop billing)
```bash
kubectl -n traefik delete svc traefik          # free the NLB before destroy
cd terraform/environments/dev && terraform destroy    # (add -var 'create_apex_record=true' if it was set)
```
State bucket + Route 53 zone remain (cheap). To fully remove: delete the zone + `aws s3 rb`.

## Quick troubleshooting
| Symptom | Fix |
|---|---|
| `permission denied .terraform/...` | root-owned dir — use `TF_DATA_DIR` or `sudo rm -rf` it (Pre-flight note) |
| pods `ImagePullBackOff` | CI (step 3) hasn't bumped `values.yaml` yet — wait for it green, then Argo re-syncs |
| Argo app `ComparisonError` repo not found | repo Secret / PAT wrong (step 4) |
| `certificate` stuck `READY=False` | DNS not resolving yet (step 6) — HTTP-01 needs public DNS |
| gp2 SC sync conflict | our `deploy/cluster/storage/gp2.yaml` matches EKS's gp2 (verified) — should not occur |
