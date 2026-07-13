# Terraform — Banking Platform Infrastructure

Modular Terraform that provisions the **AWS** foundation for the platform.
Kubernetes add-ons (Traefik, cert-manager, ArgoCD, observability) are **not**
managed here — they are Helm charts/manifests applied via GitOps (see `deploy/`).

## Layout

```
terraform/
├── modules/
│   ├── vpc/     # VPC, public/private subnets, IGW, NAT, routes, EKS subnet tags
│   ├── iam/     # EKS cluster role, node role, ECR push policy
│   ├── eks/     # EKS cluster + managed node groups + OIDC   (Phase 9)
│   ├── ecr/     # per-service ECR repositories               (Phase 9)
│   └── s3/      # document/statement buckets                 (Phase 9)
└── environments/
    ├── dev/     # 10.10.0.0/16, single NAT
    ├── qa/      # 10.20.0.0/16, single NAT
    └── prod/    # 10.30.0.0/16, one NAT per AZ (HA)
```

## Usage

Each environment is a root module.

```bash
cd environments/dev

# One-time offline check (no AWS creds needed):
terraform init -backend=false && terraform validate

# Real usage (needs AWS credentials + the S3 state bucket to exist):
terraform init      # configures the S3 backend from backend.tf
terraform plan
terraform apply
```

## Remote state (bootstrap once)

`backend.tf` expects an S3 bucket `banking-platform-tfstate` and a DynamoDB lock
table `banking-platform-tflock`. Create these once (console or a tiny bootstrap
config) before the first `terraform init` with the backend enabled.

## Notes

- No managed AWS data services (RDS/MSK/ElastiCache) — Postgres/Redis/Kafka run
  in-cluster per the project's learning goal. Terraform provisions VPC, IAM, EKS,
  ECR and S3 only.
- `terraform validate`/`fmt` run in CI with no credentials; `plan`/`apply`
  require credentials and are run deliberately by an operator.
