output "bucket_name" {
  description = "S3 bucket holding Velero backups."
  value       = aws_s3_bucket.this.bucket
}

output "irsa_role_arn" {
  description = "IAM role ARN assumed by the velero ServiceAccount (annotate it on the SA)."
  value       = aws_iam_role.velero.arn
}
