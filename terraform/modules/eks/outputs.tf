output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 CA data for the cluster."
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_security_group_id" {
  description = "Cluster security group ID."
  value       = module.eks.cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA."
  value       = module.eks.oidc_provider_arn
}

output "ebs_csi_irsa_role_arn" {
  description = "IRSA role ARN assumed by the EBS CSI driver controller."
  value       = aws_iam_role.ebs_csi.arn
}
