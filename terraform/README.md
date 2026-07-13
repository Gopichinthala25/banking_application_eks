# Terraform — Banking Platform Infrastructure

Modular Terraform that provisions the **AWS** foundation for the platform.
Kubernetes add-ons (Traefik, cert-manager, Argo CD, observability) are **not**
managed here — they are Helm charts/manifests applied via GitOps (see `deploy/`).

Full walkthrough: [docs/aws/01-terraform-infra.md](../docs/aws/01-terraform-infra.md).

## Layout

```
terraform/
├── modules/
│   ├── vpc/     # VPC, public/private subnets, IGW, NAT, routes, EKS subnet tags
│   ├── iam/     # EKS cluster role, node role, ECR push policy
│   ├── eks/     # EKS cluster + managed node group + OIDC + EBS CSI add-on
│   ├── ecr/     # ONE ECR repository (tag-prefix per service) + lifecycle policy
│   ├── s3/      # document/statement bucket (private, encrypted, versioned)
│   └── route53/ # apex hosted zone (+ optional apex ALIAS -> Traefik NLB)
└── environments/
    ├── dev/     # 10.10.0.0/16, single NAT   ← we deploy the app from here
    ├── qa/      # 10.20.0.0/16, single NAT
    └── prod/    # 10.30.0.0/16, one NAT per AZ (HA)
```

## Remote state (bootstrap once, before the first backend `init`)

`backend.tf` stores state in an S3 bucket `banking-platform-tfstate` with
`use_lockfile` native locking (Terraform **≥ 1.10** — no DynamoDB). Create just
the bucket once:

```bash
aws s3api create-bucket --bucket banking-platform-tfstate --region us-east-1
aws s3api put-bucket-versioning --bucket banking-platform-tfstate \
  --versioning-configuration Status=Enabled
```

## Usage — deploy the dev environment

We deploy the banking platform from **`environments/dev`**.

```bash
cd terraform/environments/dev

# 0) Offline sanity check (no AWS creds needed)
terraform init -backend=false && terraform validate

# 1) Init with the real S3 backend (bucket from "Remote state" above must exist)
terraform init
```

### Phase 1 — cheap validation run (prove the infra, save money)

Small nodes, max 2 — just enough to confirm the cluster + add-ons come up, then
tear it down. Don't deploy the app on this.

```bash
terraform apply \
  -var 'node_instance_types=["t3.medium"]' \
  -var 'node_min_size=1' -var 'node_desired_size=2' -var 'node_max_size=2'
# (equivalently: terraform apply -var-file=cheap-test.tfvars  — a local, gitignored helper)

# once satisfied it applies cleanly:
terraform destroy
```

### Phase 2 — real run (full banking sizing)

Plain apply uses the committed defaults (`t3.xlarge`, min 3 / desired 4 / max 6):

```bash
terraform plan
terraform apply
```

### After Traefik is installed (Phase 2 of the deploy) — add the apex DNS record

```bash
terraform apply -var 'create_apex_record=true'   # apex ALIAS -> Traefik NLB
```

### Read outputs (nameservers to delegate at GoDaddy, ECR URL, etc.)

```bash
terraform output
# route53_name_servers = [...]   # paste into GoDaddy
# ecr_repository_url   = "<acct>.dkr.ecr.us-east-1.amazonaws.com/banking-platform"
# cluster_name         = "banking-dev"
```

## Notes

- No managed AWS data services (RDS/MSK/ElastiCache) — Postgres/Redis/Kafka run
  in-cluster per the project's learning goal. Terraform provisions VPC, IAM, EKS,
  ECR, S3 and Route 53 only.
- `terraform validate`/`fmt` run in CI with no credentials; `plan`/`apply`
  require credentials and are run deliberately by an operator.
- The EBS CSI driver is a managed add-on here; the default `gp3` StorageClass is
  applied via GitOps (`deploy/cluster/storage`), keeping Terraform AWS-only.
