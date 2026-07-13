# EKS cluster via the community module. Nodes run in the private subnets; IRSA is
# enabled so pods (e.g. document-service for S3) can assume IAM roles. The
# control-plane and node IAM roles come from the iam module (Phase 8).

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.24"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true
  authentication_mode                      = "API_AND_CONFIG_MAP"
  enable_irsa                              = true

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  # Reuse the control-plane role created by the iam module.
  create_iam_role = false
  iam_role_arn    = var.cluster_role_arn

  eks_managed_node_group_defaults = {
    ami_type = "AL2023_x86_64_STANDARD"
  }

  eks_managed_node_groups = {
    default = {
      min_size       = var.node_min_size
      max_size       = var.node_max_size
      desired_size   = var.node_desired_size
      instance_types = var.node_instance_types
      capacity_type  = "ON_DEMAND"

      # Reuse the node role created by the iam module.
      create_iam_role = false
      iam_role_arn    = var.node_role_arn
    }
  }

  cluster_addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni    = {}
  }

  tags = var.tags
}
