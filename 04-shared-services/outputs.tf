# ============================================
# Outputs — Values for Week 6 (Data Platform) and Operations
# ============================================

# CloudTrail
output "cloudtrail_bucket_name" {
  value       = aws_s3_bucket.cloudtrail_logs.id
  description = "CloudTrail S3 bucket name for log analysis"
}

output "cloudtrail_bucket_arn" {
  value       = aws_s3_bucket.cloudtrail_logs.arn
  description = "CloudTrail S3 bucket ARN for IAM policies"
}

output "organization_trail_arn" {
  value       = aws_cloudtrail.organization.arn
  description = "Organization CloudTrail ARN"
}

# AWS Config
output "config_bucket_name" {
  value       = aws_s3_bucket.config_logs.id
  description = "AWS Config S3 bucket name for compliance reports"
}

output "config_recorder_name" {
  value       = aws_config_configuration_recorder.main.name
  description = "AWS Config recorder name"
}

output "config_rules" {
  value = [
    aws_config_config_rule.encrypted_volumes.name,
    aws_config_config_rule.rds_encryption.name,
    aws_config_config_rule.s3_public_read.name,
    aws_config_config_rule.restricted_ssh.name
  ]
  description = "AWS Config rule names for compliance monitoring"
}

# CloudWatch Dashboards
output "production_dashboard_name" {
  value       = aws_cloudwatch_dashboard.production.dashboard_name
  description = "Production overview dashboard name"
}

output "security_dashboard_name" {
  value       = aws_cloudwatch_dashboard.security.dashboard_name
  description = "Security overview dashboard name"
}

# VPC Flow Logs
output "flow_logs_bucket_name" {
  value       = aws_s3_bucket.flow_logs.id
  description = "VPC Flow Logs S3 bucket name"
}

output "flow_logs_bucket_arn" {
  value       = aws_s3_bucket.flow_logs.arn
  description = "VPC Flow Logs S3 bucket ARN for IAM policies"
}

# Cross-Account IAM Roles
output "operations_role_arn" {
  value       = aws_iam_role.operations.arn
  description = "Cross-account operations role ARN"
}

output "security_audit_role_arn" {
  value       = aws_iam_role.security_audit.arn
  description = "Cross-account security audit role ARN"
}

output "billing_role_arn" {
  value       = aws_iam_role.billing.arn
  description = "Cross-account billing role ARN"
}

# SNS Topics
output "config_alerts_topic_arn" {
  value       = aws_sns_topic.config_alerts.arn
  description = "AWS Config alerts SNS topic ARN"
}

# Summary
output "week_4_summary" {
  value = {
    organization_trail_created = true
    cloudtrail_multi_region    = true
    config_rules_created       = 4
    cloudwatch_dashboards      = 2
    vpc_flow_logs_enabled      = var.enable_vpc_flow_logs
    cross_account_roles        = 3
    log_retention_days         = var.log_retention_days
    s3_log_buckets_created     = 3
  }
  description = "Summary of all Week 4 shared services resources"
}

# ============================================
# ADDITION TO Week 4: 04-shared-services/outputs.tf
# ============================================

output "cloudtrail_bucket_name" {
  value       = aws_s3_bucket.cloudtrail.id
  description = "CloudTrail S3 bucket name for Week 8 DR replication source"
}

output "cloudtrail_bucket_arn" {
  value       = aws_s3_bucket.cloudtrail.arn
  description = "CloudTrail S3 bucket ARN for replication policy"
}

output "config_bucket_name" {
  value       = aws_s3_bucket.config_logs.id
  description = "AWS Config S3 bucket name for Week 8 DR replication source"
}

output "config_bucket_arn" {
  value       = aws_s3_bucket.config_logs.arn
  description = "AWS Config S3 bucket ARN for replication policy"
}

output "flow_logs_bucket_name" {
  value       = aws_s3_bucket.flow_logs.id
  description = "VPC Flow Logs S3 bucket name"
}

output "flow_logs_bucket_arn" {
  value       = aws_s3_bucket.flow_logs.arn
  description = "VPC Flow Logs S3 bucket ARN for replication policy"
}