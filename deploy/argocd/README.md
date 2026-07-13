# Argo CD GitOps (app-of-apps)

Everything the cluster runs is declared here and reconciled by Argo CD
(automated sync + prune + selfHeal). You apply **two** files once; Argo CD does
the rest.

```
deploy/argocd/
├── bootstrap/
│   ├── project.yaml     # AppProject "banking" (allowed repos + namespaces)
│   └── root-app.yaml    # app-of-apps → watches apps/ and creates everything below
└── apps/
    ├── banking-platform.yaml          # our umbrella Helm chart  → ns banking
    ├── cert-manager.yaml              # Let's Encrypt TLS         → ns cert-manager
    └── observability/
        ├── kube-prometheus-stack.yaml # Prometheus/Grafana/Alertmanager → ns observability
        ├── loki-stack.yaml            # logs
        ├── tempo.yaml                 # traces
        ├── otel-collector.yaml        # OTLP ingest
        └── extras.yaml                # ServiceMonitor + dashboards (raw manifests)
```

## 1. Set your repo URL (one-time)

Every Application points at this git repo. Replace the placeholder everywhere:

```bash
# from the repo root — set to your actual GitHub repo
grep -rl 'YOUR_GH_USER/banking-platform' deploy/argocd \
  | xargs sed -i 's#https://github.com/YOUR_GH_USER/banking-platform.git#https://github.com/<you>/banking-platform.git#g'
```

Commit the change so Argo CD (which reads from git) sees the right URL.

> Private repo? Give Argo CD credentials first — see docs/aws/04-argocd.md Step 4
> (labeled `repository` Secret with a classic PAT).

## 2. Bootstrap (apply once)

Prereq: Argo CD is installed (docs/aws/04-argocd.md Step 2).

```bash
kubectl apply -f deploy/argocd/bootstrap/project.yaml
kubectl apply -f deploy/argocd/bootstrap/root-app.yaml
```

`platform-root` clones the repo, reads `apps/` (recursively), and creates every
Application. Watch them appear:

```bash
kubectl -n argocd get applications
# platform-root, banking-platform, cert-manager,
# kube-prometheus-stack, loki-stack, tempo, otel-collector, observability-extras
```

## 3. From here on, it's GitOps

- **Deploy a code change:** CI builds the image and bumps
  `deploy/helm/banking-platform/values.yaml`; Argo CD syncs it. No kubectl.
- **Add a new managed component:** drop an `Application` YAML into `apps/`
  (or `apps/observability/`), commit — `platform-root` creates it automatically.
- **Remove one:** delete its file, commit — prune removes it.

## Notes

- **Chart versions:** the observability Applications use `targetRevision: "*"`
  (latest), matching `deploy/observability/install.sh`. **Pin these to tested
  versions for production** (replace `"*"` with the chart version).
- **Observability values** live in `deploy/observability/values/*.yaml` and are
  pulled into each chart via a multi-source `$values` ref — the same files
  `install.sh` uses, so the two install paths stay identical.
- **`install.sh` is the non-GitOps fallback** for a quick manual install; the
  app-of-apps here is the primary, reconciled path.
- **StatefulSet PVCs:** `banking-platform.yaml` ignores
  `/spec/volumeClaimTemplates` diffs (immutable) so Postgres/Kafka don't sit
  perpetually OutOfSync.
