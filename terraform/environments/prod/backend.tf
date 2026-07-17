terraform {
  backend "s3" {
    bucket       = "banking-platform-tfstate-118178010323"
    key          = "prod/networking.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
