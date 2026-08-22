# ============================================
# KMS Keys — Encryption for Data at Rest
# ============================================

resource "aws_kms_key" "rds" {
  description             = "KMS key for RDS Aurora cluster encryption"
  deletion_window_in_days = var.kms_deletion_window
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_rds.json

  tags = merge(local.common_tags, {
    Name = local.kms_aliases.rds
    Type = "Database-Encryption"
  })
}

resource "aws_kms_alias" "rds" {
  name          = local.kms_aliases.rds
  target_key_id = aws_kms_key.rds.key_id
}

resource "aws_kms_key" "s3" {
  description             = "KMS key for S3 bucket server-side encryption"
  deletion_window_in_days = var.kms_deletion_window
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_s3.json

  tags = merge(local.common_tags, {
    Name = local.kms_aliases.s3
    Type = "Storage-Encryption"
  })
}

resource "aws_kms_alias" "s3" {
  name          = local.kms_aliases.s3
  target_key_id = aws_kms_key.s3.key_id
}

resource "aws_kms_key" "secrets" {
  description             = "KMS key for Secrets Manager encryption"
  deletion_window_in_days = var.kms_deletion_window
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_secrets.json

  tags = merge(local.common_tags, {
    Name = local.kms_aliases.secrets
    Type = "Secret-Encryption"
  })
}

resource "aws_kms_alias" "secrets" {
  name          = local.kms_aliases.secrets
  target_key_id = aws_kms_key.secrets.key_id
}

resource "aws_kms_key" "lambda" {
  description             = "KMS key for Lambda environment variable encryption"
  deletion_window_in_days = var.kms_deletion_window
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_lambda.json

  tags = merge(local.common_tags, {
    Name = local.kms_aliases.lambda
    Type = "Compute-Encryption"
  })
}

resource "aws_kms_alias" "lambda" {
  name          = local.kms_aliases.lambda
  target_key_id = aws_kms_key.lambda.key_id
}

resource "aws_kms_key" "cloudtrail" {
  description             = "KMS key for CloudTrail log file encryption"
  deletion_window_in_days = var.kms_deletion_window
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_cloudtrail.json

  tags = merge(local.common_tags, {
    Name = local.kms_aliases.cloudtrail
    Type = "Audit-Encryption"
  })
}

resource "aws_kms_alias" "cloudtrail" {
  name          = local.kms_aliases.cloudtrail
  target_key_id = aws_kms_key.cloudtrail.key_id
}

# KMS Key for EKS Kubernetes Secrets Encryption
resource "aws_kms_key" "eks" {
  description             = "KMS key for EKS Kubernetes secrets encryption"
  deletion_window_in_days = var.kms_deletion_window
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_eks.json

  tags = merge(local.common_tags, {
    Name = local.kms_aliases.eks
    Type = "Kubernetes-Encryption"
  })
}

resource "aws_kms_alias" "eks" {
  name          = local.kms_aliases.eks
  target_key_id = aws_kms_key.eks.key_id
}

# KMS Key for EBS Volume Encryption
resource "aws_kms_key" "ebs" {
  description             = "KMS key for EBS volume encryption (EKS nodes, EC2)"
  deletion_window_in_days = var.kms_deletion_window
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_ebs.json

  tags = merge(local.common_tags, {
    Name = local.kms_aliases.ebs
    Type = "Storage-Encryption"
  })
}

resource "aws_kms_alias" "ebs" {
  name          = local.kms_aliases.ebs
  target_key_id = aws_kms_key.ebs.key_id
}