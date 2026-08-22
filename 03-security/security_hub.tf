# ============================================
# AWS Security Hub — Central Security Dashboard
# ============================================

# Security Hub Account — Enable the service
resource "aws_securityhub_account" "main" {
  count = var.enable_security_hub ? 1 : 0

  enable_default_standards = false
}

# Security Hub Standards — Compliance frameworks
resource "aws_securityhub_standards_subscription" "aws_foundational" {
  count = var.enable_security_hub ? 1 : 0

  standards_arn = "arn:aws:securityhub:${var.primary_region}::standards/aws-foundational-security-best-practices/v/1.0.0"

  depends_on = [aws_securityhub_account.main]
}

resource "aws_securityhub_standards_subscription" "cis" {
  count = var.enable_security_hub ? 1 : 0

  standards_arn = "arn:aws:securityhub:${var.primary_region}::standards/cis-aws-foundations-benchmark/v/1.4.0"

  depends_on = [aws_securityhub_account.main]
}

resource "aws_securityhub_standards_subscription" "pci_dss" {
  count = var.enable_security_hub ? 1 : 0

  standards_arn = "arn:aws:securityhub:${var.primary_region}::standards/pci-dss/v/3.2.1"

  depends_on = [aws_securityhub_account.main]
}

# Security Hub Organization Admin — Centralize across all accounts
resource "aws_securityhub_organization_admin_account" "main" {
  count = var.enable_security_hub ? 1 : 0

  admin_account_id = data.aws_caller_identity.current.account_id

  depends_on = [aws_securityhub_account.main]
}

# Security Hub Organization Configuration — Auto-enable for new accounts
resource "aws_securityhub_organization_configuration" "main" {
  count = var.enable_security_hub ? 1 : 0

  auto_enable = true

  depends_on = [aws_securityhub_organization_admin_account.main]
}

# Security Hub Insight — Critical unresolved findings
resource "aws_securityhub_insight" "critical_findings" {
  count = var.enable_security_hub ? 1 : 0

  name               = "ABSA-Critical-Findings"
  group_by_attribute = "SeverityLabel"

  filters {
    severity_label {
      comparison = "EQUALS"
      value      = "CRITICAL"
    }
    record_state {
      comparison = "EQUALS"
      value      = "ACTIVE"
    }
    workflow_status {
      comparison = "NOT_EQUALS"
      value      = "RESOLVED"
    }
  }

  depends_on = [aws_securityhub_account.main]
}

# Security Hub Insight — Public S3 buckets
resource "aws_securityhub_insight" "public_s3" {
  count = var.enable_security_hub ? 1 : 0

  name               = "ABSA-Public-S3-Buckets"
  group_by_attribute = "ResourceId"

  filters {
    title {
      comparison = "PREFIX"
      value      = "S3"
    }
    record_state {
      comparison = "EQUALS"
      value      = "ACTIVE"
    }
    workflow_status {
      comparison = "NOT_EQUALS"
      value      = "RESOLVED"
    }
    compliance_status {
      comparison = "EQUALS"
      value      = "FAILED"
    }
  }

  depends_on = [aws_securityhub_account.main]
}

# Security Hub Insight — Encryption issues
resource "aws_securityhub_insight" "encryption_issues" {
  count = var.enable_security_hub ? 1 : 0

  name               = "ABSA-Encryption-Issues"
  group_by_attribute = "ResourceType"

  filters {
    title {
      comparison = "PREFIX"
      value      = "Encryption"
    }
    record_state {
      comparison = "EQUALS"
      value      = "ACTIVE"
    }
    workflow_status {
      comparison = "NOT_EQUALS"
      value      = "RESOLVED"
    }
    compliance_status {
      comparison = "EQUALS"
      value      = "FAILED"
    }
  }

  depends_on = [aws_securityhub_account.main]
}

# Action Target — Auto-remediate findings with Lambda
resource "aws_securityhub_action_target" "auto_remediate" {
  count = var.enable_security_hub ? 1 : 0

  name        = "ABSA-Auto-Remediate"
  identifier  = "ABSA-Auto-Remediate"
  description = "Triggers Lambda to automatically fix the finding"

  depends_on = [aws_securityhub_account.main]
}