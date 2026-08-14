# Velero has its OWN state (separate key in the same bucket), so it can be
# applied/destroyed independently of the Phase-1 infra state.
terraform {
  backend "s3" {
    bucket       = "backend-terraform-store123"
    key          = "dev/velero.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
