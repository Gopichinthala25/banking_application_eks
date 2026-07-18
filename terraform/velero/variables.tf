variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (for tagging)."
  type        = string
  default     = "dev"
}

variable "name" {
  description = "Resource name prefix."
  type        = string
  default     = "banking-dev"
}

variable "cluster_name" {
  description = "Existing EKS cluster to read the OIDC provider from."
  type        = string
  default     = "banking-dev"
}
