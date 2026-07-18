variable "name" {
  description = "Resource name prefix (e.g. banking-dev)."
  type        = string
}

variable "bucket_name" {
  description = "Globally-unique S3 bucket name for Velero backups."
  type        = string
}

variable "oidc_provider_arn" {
  description = "EKS cluster OIDC provider ARN (for the IRSA trust policy)."
  type        = string
}

variable "oidc_provider" {
  description = "EKS cluster OIDC issuer URL WITHOUT the https:// prefix."
  type        = string
}

variable "tags" {
  description = "Common tags."
  type        = map(string)
  default     = {}
}
