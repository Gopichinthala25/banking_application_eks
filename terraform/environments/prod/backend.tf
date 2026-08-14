terraform {
  backend "s3" {
    bucket       = "backend-terraform-store123"
    key          = "prod/networking.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
