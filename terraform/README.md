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

## Remote state (bootstrap once — BEFORE `terraform init`)

`backend.tf` stores state in an S3 bucket with `use_lockfile` native locking
(Terraform ≥ 1.10 — no DynamoDB). Create the bucket **once**, before the first
`terraform init` with the backend enabled:

```bash
REGION=us-east-1
aws s3api create-bucket --bucket banking-platform-tfstate-118178010323 --region $REGION
aws s3api put-bucket-versioning --bucket banking-platform-tfstate-118178010323 \
  --versioning-configuration Status=Enabled
```

**Where the bucket name lives:** in each environment's `backend.tf`
(`environments/dev/backend.tf`, `qa/`, `prod/`). All three share one bucket and
differ only by `key`. If you want a different bucket name, change the `bucket`
line in each:

```hcl
terraform {
  backend "s3" {
    bucket       = "banking-platform-tfstate-118178010323"   # 👈 your bucket name (must match the one you created)
    key          = "dev/networking.tfstate"     #    per-env state path
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
```

## Notes

- No managed AWS data services (RDS/MSK/ElastiCache) — Postgres/Redis/Kafka run
  in-cluster per the project's learning goal. Terraform provisions VPC, IAM, EKS,
  ECR and S3 only.
- `terraform validate`/`fmt` run in CI with no credentials; `plan`/`apply`
  require credentials and are run deliberately by an operator.
