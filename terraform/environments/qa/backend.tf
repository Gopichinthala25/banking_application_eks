terraform {
  backend "s3" {
    bucket         = "banking-platform-tfstate"
    key            = "qa/networking.tfstate"
    region         = "us-east-1"
    dynamodb_table = "banking-platform-tflock"
    encrypt        = true
  }
}
