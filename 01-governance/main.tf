terraform {
  required_version = ">= 1.8.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.22.0"
    }
  }
}

# Root Organization — Establish the multi-account foundation
resource "aws_organizations_organization" "absa" {
  feature_set          = "ALL"
  enabled_policy_types = [
    "SERVICE_CONTROL_POLICY",
    "TAG_POLICY",
    "BACKUP_POLICY",
    "AISERVICES_OPT_OUT_POLICY"
  ]

  # Enable trusted access for governance services
  aws_service_access_principals = [
    "cloudtrail.amazonaws.com",
    "config.amazonaws.com",
    "sso.amazonaws.com",
    "guardduty.amazonaws.com",
    "securityhub.amazonaws.com",
    "controltower.amazonaws.com",
    "ram.amazonaws.com"
  ]
}

# Control Tower Landing Zone — Automates guardrails and account provisioning
resource "aws_controltower_landing_zone" "absa" {
  manifest_json = jsonencode({
    governedRegions = ["eu-west-1", "eu-west-2", "af-south-1"]
    organizationStructure = {
      security = { name = "Security" }
      shared_services = { name = "Shared-Services" }
    }
    centralizedLogging = {
      accountId = aws_organizations_account.log_archive.id
      configurations = {
        loggingBucket      = { retentionDays = 365 }
        accessLoggingBucket = { retentionDays = 3650 }
      }
      enabled = true
    }
    securityRoles = {
      accountId = aws_organizations_account.audit.id
    }
    accessManagement = {
      enabled = true
    }
  })
  version = "3.3"
}

# Log Archive Account (Control Tower mandatory)
resource "aws_organizations_account" "log_archive" {
  name       = "ABSA-Log-Archive"
  email      = var.log_archive_email
  parent_id  = aws_organizations_organizational_unit.shared_services.id
  role_name  = "OrganizationAccountAccessRole"
  tags = {
    Environment = "Management"
    Owner       = "Cloud-CoE"
  }
}

# Audit Account (Control Tower mandatory)
resource "aws_organizations_account" "audit" {
  name       = "ABSA-Audit"
  email      = var.audit_email
  parent_id  = aws_organizations_organizational_unit.shared_services.id
  role_name  = "OrganizationAccountAccessRole"
  tags = {
    Environment = "Management"
    Owner       = "Security-Team"
  }
}