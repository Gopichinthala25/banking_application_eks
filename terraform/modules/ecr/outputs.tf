output "repository_url" {
  description = "URL of the single ECR repository (push as <url>:<service>-<tag>)."
  value       = aws_ecr_repository.this.repository_url
}

output "repository_arn" {
  description = "ARN of the ECR repository."
  value       = aws_ecr_repository.this.arn
}
