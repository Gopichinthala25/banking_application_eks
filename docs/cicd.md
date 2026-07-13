# CI/CD

GitHub Actions builds, tests, scans and publishes images, then bumps the Helm
image tag so Argo CD deploys the new version (GitOps).

## Workflows
- **`.github/workflows/ci.yaml`** — the application pipeline.
- **`.github/workflows/terraform.yaml`** — `fmt`/`init`/`validate` for dev/qa/prod (no apply).

## CI/CD flow

```
push to main
   │
   ├─ changes  ──── detect changed services (shared change → build all)
   │
   ├─ build (matrix per service)
   │     go test + vet → docker build (build/service.Dockerfile) →
   │     Trivy scan (CRITICAL/HIGH) → push  <ecr>/<repo>:<service>-<sha>
   │
   ├─ frontend   (React → docker → Trivy → push :frontend-<sha>)
   │
   └─ bump-and-commit
         yq patch <service>.image for each REBUILT service in values.yaml
         (→ <ecr>/<repo>:<service>-<sha>) → commit [skip ci]
                                   │
                                   ▼
                            Argo CD detects the change → syncs → EKS
```

## Design notes
- **Single ECR repository**: every service pushes to one repo, distinguished by
  tag prefix `<service>-<sha>`.
- The Helm chart is **one explicit file per service** with a flat `values.yaml`;
  each service block has its own `image:` string. The bump step patches only the
  services rebuilt in that run (unchanged services keep their previous image).
- **Change detection**: only changed services build; a change to `pkg/`,
  `proto/`, `go.work`, `build/`, or the workflow rebuilds everything.
- **Trivy** fails the build on fixable CRITICAL/HIGH vulnerabilities
  (`ignore-unfixed: true`). No OWASP Dependency-Check (per project scope).
- **AWS auth via OIDC** (`aws-actions/configure-aws-credentials` with
  `role-to-assume`) — no long-lived keys.
- PRs run test + build + scan but **do not push** or bump.

## Required repository configuration
Settings → Secrets and variables → Actions:

| Kind | Name | Example |
|------|------|---------|
| Variable | `AWS_REGION` | `us-east-1` |
| Variable | `ECR_REGISTRY` | `<acct>.dkr.ecr.us-east-1.amazonaws.com` |
| Variable | `ECR_REPOSITORY` | `banking-platform` |
| Secret | `AWS_ACCESS_KEY_ID` | IAM user access key |
| Secret | `AWS_SECRET_ACCESS_KEY` | matching secret key |

The IAM user carries the ECR push policy created by `terraform/modules/iam`.
(For a hardening upgrade later, swap the static keys for GitHub OIDC with
`role-to-assume` — no long-lived credentials.)
