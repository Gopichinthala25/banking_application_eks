# Velero AWS resources: an S3 bucket for backups + an IAM policy + an IRSA role
# assumed by the velero ServiceAccount (velero/velero). No static credentials.
#
# This module is OPTIONAL and deliberately NOT wired into environments/* — it is
# applied on its own from terraform/velero/ when setting up backup/DR (Phase 8),
# so the core infra apply never creates it.

resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name
  tags   = var.tags
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 (backup store) + EC2 snapshot perms (for the optional CSI/EBS snapshot mode).
data "aws_iam_policy_document" "velero" {
  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeVolumes",
      "ec2:DescribeSnapshots",
      "ec2:CreateTags",
      "ec2:CreateVolume",
      "ec2:CreateSnapshot",
      "ec2:DeleteSnapshot",
    ]
    resources = ["*"]
  }
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:PutObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]
    resources = ["${aws_s3_bucket.this.arn}/*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.this.arn]
  }
}

resource "aws_iam_policy" "velero" {
  name   = "${var.name}-velero"
  policy = data.aws_iam_policy_document.velero.json
  tags   = var.tags
}

# IRSA trust: the velero/velero ServiceAccount assumes this role via the cluster OIDC.
data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider}:sub"
      values   = ["system:serviceaccount:velero:velero"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "velero" {
  name               = "${var.name}-velero-irsa"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "velero" {
  role       = aws_iam_role.velero.name
  policy_arn = aws_iam_policy.velero.arn
}
