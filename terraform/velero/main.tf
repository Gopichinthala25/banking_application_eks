# Standalone root for Velero's AWS resources. Reads the EXISTING cluster's OIDC
# provider via data sources (no dependency on the Phase-1 state), then calls the
# reusable velero module. Apply this on its own: `cd terraform/velero && terraform apply`.

data "aws_caller_identity" "current" {}

# Look up the running cluster to derive its OIDC issuer (for IRSA).
data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

locals {
  oidc_issuer   = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
  oidc_provider = replace(local.oidc_issuer, "https://", "")
  oidc_arn      = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.oidc_provider}"
  bucket_name   = "banking-velero-backups-${data.aws_caller_identity.current.account_id}"
}

module "velero" {
  source = "../modules/velero"

  name              = var.name
  bucket_name       = local.bucket_name
  oidc_provider_arn = local.oidc_arn
  oidc_provider     = local.oidc_provider
}
