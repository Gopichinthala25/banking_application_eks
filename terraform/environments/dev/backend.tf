# Remote state in S3 with DynamoDB locking.
#
# The bucket + lock table must exist first (bootstrap once, out of band). For
# offline validation we run `terraform init -backend=false`, so this block is
# inert until you configure and init with a real backend.
terraform {
  backend "s3" {
    bucket         = "banking-platform-tfstate" # create once, then set here
    key            = "dev/networking.tfstate"
    region         = "us-east-1"
    dynamodb_table = "banking-platform-tflock"
    encrypt        = true
  }
}
