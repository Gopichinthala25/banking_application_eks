output "velero_bucket" {
  description = "S3 bucket for Velero backups."
  value       = module.velero.bucket_name
}

output "velero_irsa_role_arn" {
  description = "IRSA role ARN — annotate it on the velero ServiceAccount."
  value       = module.velero.irsa_role_arn
}
