# Velero — AWS resources (standalone Terraform stack)

This is an **optional, standalone** Terraform stack that provisions the **AWS
resources Velero needs** for cluster backup & disaster recovery on EKS. It is
**deliberately separate** from the core infrastructure in
[`../environments/dev`](../environments/dev):

- It has its **own state file** (`dev/velero.tfstate` in the shared state bucket),
  so it can be applied and destroyed **independently** of the cluster.
- A normal core-infra `terraform apply` (in `environments/dev`) **never** creates
  these resources — Velero is opt-in.
- It reads the **already-running cluster** via a data source (no dependency on the
  Phase-1 stack's outputs).

> This stack creates only the **AWS side**. Installing the Velero **server**
> (Helm chart / Argo CD app), taking backups, schedules, and restores are covered
> in [`docs/aws/08-velero.md`](../../docs/aws/08-velero.md).

---

## What Terraform creates here

Applying this stack (`terraform apply`) creates **6 resources** via the
[`../modules/velero`](../modules/velero) module:

| # | Resource (Terraform) | AWS resource | Purpose |
|---|----------------------|--------------|---------|
| 1 | `aws_s3_bucket.this` | **S3 bucket** `banking-velero-backups-<account-id>` | Stores Velero backups — the Kubernetes object archives **and** the kopia file-system volume data (Postgres/Kafka contents). |
| 2 | `aws_s3_bucket_versioning.this` | S3 **versioning** (Enabled) | Keeps historical versions of backup objects (protection against overwrite/corruption). |
| 3 | `aws_s3_bucket_public_access_block.this` | S3 **public-access block** (all 4 on) | Ensures backups are never publicly exposed. |
| 4 | `aws_iam_policy.velero` | **IAM policy** `banking-dev-velero` | Grants Velero: S3 read/write/list on the backup bucket **+** EC2 snapshot permissions (for the optional CSI/EBS snapshot mode). |
| 5 | `aws_iam_role.velero` | **IAM role** `banking-dev-velero-irsa` | The role the Velero pod assumes via **IRSA** — no static AWS keys in the cluster. Trust policy is scoped to the `velero/velero` ServiceAccount through the cluster's OIDC provider. |
| 6 | `aws_iam_role_policy_attachment.velero` | Policy → Role binding | Attaches the policy above to the IRSA role. |

Plus **read-only data sources** (create nothing):

| Data source | Why |
|-------------|-----|
| `aws_caller_identity.current` | Get the AWS account ID (used in the bucket name + OIDC ARN). |
| `aws_eks_cluster.this` (`banking-dev`) | Read the cluster's **OIDC issuer URL**, used to build the IRSA trust policy. This is how the stack "finds" the cluster without needing the Phase-1 state. |

### The IAM permissions granted (summary)
```
S3  (on the backup bucket only):  GetObject, PutObject, DeleteObject,
                                  ListBucket, AbortMultipartUpload,
                                  ListMultipartUploadParts
EC2 (account-wide, for snapshots): DescribeVolumes, DescribeSnapshots,
                                  CreateSnapshot, DeleteSnapshot,
                                  CreateVolume, CreateTags
```

### IRSA trust (who can assume the role)
Only the `velero` ServiceAccount in the `velero` namespace, via the cluster OIDC
provider:
```
system:serviceaccount:velero:velero   (aud: sts.amazonaws.com)
```

---

## What it does NOT do
- ❌ Does **not** install the Velero server, node-agent, or CRDs (that's the Helm
  chart / Argo app — see doc 08).
- ❌ Does **not** touch the EKS cluster, VPC, node groups, or any Phase-1 infra.
- ❌ Does **not** take backups or schedules (Velero CLI / `Schedule` CRD do that).

---

## Files in this stack
| File | Role |
|------|------|
| `backend.tf` | S3 remote state — key `dev/velero.tfstate`, native `use_lockfile` locking (no DynamoDB). |
| `providers.tf` | AWS provider + default tags (`Component = velero`). |
| `versions.tf` | Terraform ≥ 1.10, `hashicorp/aws ~> 5.60`. |
| `variables.tf` | `region`, `environment`, `name`, `cluster_name` (defaults target `banking-dev` / `us-east-1`). |
| `main.tf` | Data-source lookups + the `module "velero"` call. |
| `outputs.tf` | `velero_bucket`, `velero_irsa_role_arn`. |

---

## Prerequisites
- The **EKS cluster `banking-dev` exists** (this stack reads its OIDC provider).
- The **state bucket** `banking-platform-tfstate-118178010323` exists (created in Phase 1).
- AWS credentials configured; Terraform ≥ 1.10.

## Usage
```bash
cd terraform/velero

terraform init          # configures the S3 backend (own state: dev/velero.tfstate)
terraform plan          # review: 6 resources to add
terraform apply         # create the bucket + IAM policy + IRSA role

# Outputs used by the Velero install (doc 08):
terraform output velero_irsa_role_arn   # -> annotate on the velero ServiceAccount
terraform output velero_bucket          # -> Velero backupStorageLocation bucket
```

### Outputs and where they're used
| Output | Used in |
|--------|---------|
| `velero_irsa_role_arn` | The Velero Helm/Argo values: `serviceAccount.server.annotations."eks.amazonaws.com/role-arn"`. |
| `velero_bucket` | The Velero `backupStorageLocation.bucket`. |

## Teardown (independent of the cluster)
```bash
cd terraform/velero
terraform destroy
```
> S3 won't delete a non-empty bucket. If you want it gone, empty it first:
> `aws s3 rm s3://banking-velero-backups-118178010323 --recursive`
> (Keep the backups if you might restore into a rebuilt cluster — that's the point of DR.)

---

➡️ Full backup/restore walkthrough: [`docs/aws/08-velero.md`](../../docs/aws/08-velero.md)
