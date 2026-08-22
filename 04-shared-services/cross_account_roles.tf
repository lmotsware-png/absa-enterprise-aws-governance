# ============================================
# Cross-Account IAM Roles — Centralized Operations
# ============================================

# Operations Role — Assumed by operations team
resource "aws_iam_role" "operations" {
  name = local.operations_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = local.operations_role_name
  })
}

resource "aws_iam_role_policy_attachment" "operations_readonly" {
  role       = aws_iam_role.operations.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "operations_logging" {
  role       = aws_iam_role.operations.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccess"
}

# Security Audit Role — Assumed by security team
resource "aws_iam_role" "security_audit" {
  name = local.security_audit_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = local.security_audit_role_name
  })
}

resource "aws_iam_role_policy_attachment" "security_audit" {
  role       = aws_iam_role.security_audit.name
  policy_arn = "arn:aws:iam::aws:policy/SecurityAudit"
}

# Billing Role — Assumed by finance team
resource "aws_iam_role" "billing" {
  name = local.billing_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = local.billing_role_name
  })
}

resource "aws_iam_role_policy_attachment" "billing" {
  role       = aws_iam_role.billing.name
  policy_arn = "arn:aws:iam::aws:policy/AWSBillingReadOnlyAccess"
}