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
    ├── storage.yaml                   # gp3 default StorageClass (+ un-default gp2)
    ├── banking-platform.yaml          # our umbrella Helm chart  → ns banking
    ├── cert-manager.yaml              # Let's Encrypt TLS         → ns cert-manager
    └── observability/
        ├── kube-prometheus-stack.yaml # Prometheus/Grafana/Alertmanager → ns observability
        ├── loki-stack.yaml            # logs
        ├── tempo.yaml                 # traces
        ├── otel-collector.yaml        # OTLP ingest
        └── extras.yaml                # ServiceMonitor + dashboards (raw manifests)
```

## 1. Repo URL & credentials

Every Application already points at this repo:
`https://github.com/vijaygiduthuri/banking_application_eks.git`.

> **Private repo?** Argo CD needs read credentials or it can't clone. Add a
> labeled `repository` Secret (HTTPS + a classic PAT) — see
> docs/aws/04-argocd.md Step 4. If the repo is public, no credentials are needed.

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
# platform-root, cluster-storage, metrics-server, banking-platform, cert-manager, cert-manager-issuer,
# kube-prometheus-stack, loki-stack, tempo, otel-collector, observability-extras, velero
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
