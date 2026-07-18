provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "banking-platform"
      Environment = var.environment
      ManagedBy   = "terraform"
      Component   = "velero"
    }
  }
}
