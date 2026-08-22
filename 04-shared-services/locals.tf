locals {
  common_tags = {
    Project     = "ABSA-Enterprise-AWS"
    CostCenter  = "Cloud-Operations"
    DataClass   = "Management"
    ManagedBy   = "Terraform"
  }

  # Organization ID from Week 1
  organization_id = data.terraform_remote_state.governance.outputs.organization_id

  # All VPC IDs from Week 2
  all_vpc_ids = data.terraform_remote_state.networking.outputs.vpc_ids

  # S3 bucket names
  cloudtrail_bucket    = "absa-cloudtrail-logs-${data.aws_caller_identity.current.account_id}"
  config_bucket        = "absa-config-logs-${data.aws_caller_identity.current.account_id}"
  vpc_flow_logs_bucket = "absa-vpc-flow-logs-${data.aws_caller_identity.current.account_id}"
  alb_logs_bucket      = "absa-alb-logs-${data.aws_caller_identity.current.account_id}"

  # KMS key for log encryption — From Week 3
  kms_cloudtrail_arn = data.terraform_remote_state.security.outputs.kms_key_arns.cloudtrail

  # Cross-account role names
  operations_role_name = "ABSA-Cross-Account-Operations"
  security_audit_role_name = "ABSA-Cross-Account-Security-Audit"
  billing_role_name    = "ABSA-Cross-Account-Billing"
}

data "aws_caller_identity" "current" {}