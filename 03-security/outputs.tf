# ============================================
# Outputs — Values for Week 4 (Production Layer)
# ============================================

# KMS Key ARNs
output "kms_key_arns" {
  value = {
    rds        = aws_kms_key.rds.arn
    s3         = aws_kms_key.s3.arn
    secrets    = aws_kms_key.secrets.arn
    lambda     = aws_kms_key.lambda.arn
    cloudtrail = aws_kms_key.cloudtrail.arn
    eks        = aws_kms_key.eks.arn
     ebs       = aws_kms_key.ebs.arn  
  }
  description = "KMS key ARNs for encrypting Week 4 resources (RDS, S3, Lambda)"
}

output "kms_key_ids" {
  value = {
    rds        = aws_kms_key.rds.key_id
    s3         = aws_kms_key.s3.key_id
    secrets    = aws_kms_key.secrets.key_id
    lambda     = aws_kms_key.lambda.key_id
    cloudtrail = aws_kms_key.cloudtrail.key_id
    eks        = aws_kms_key.eks.key_id 
    ebs        = aws_kms_key.ebs.key_id
  }
  description = "KMS key IDs for direct key references"
}

output "kms_aliases" {
  value = {
    rds        = aws_kms_alias.rds.name
    s3         = aws_kms_alias.s3.name
    secrets    = aws_kms_alias.secrets.name
    lambda     = aws_kms_alias.lambda.name
    cloudtrail = aws_kms_alias.cloudtrail.name
    eks        = aws_kms_alias.eks.name
    ebs        = aws_kms_alias.ebs.name
  }
  description = "KMS key aliases for application configuration"
}

# IAM Role ARNs
output "iam_role_arns" {
  value = {
    eks_cluster     = aws_iam_role.eks_cluster.arn
    eks_node        = aws_iam_role.eks_node.arn
    lambda_exec     = aws_iam_role.lambda_exec.arn
    secrets_manager = aws_iam_role.secrets_manager.arn
    cloudtrail      = aws_iam_role.cloudtrail.arn
    config          = aws_iam_role.config.arn
    remediation     = aws_iam_role.remediation.arn
  }
  description = "IAM role ARNs for Week 4 EKS cluster, Lambda functions, and service roles"
}

output "iam_role_names" {
  value = {
    eks_cluster     = aws_iam_role.eks_cluster.name
    eks_node        = aws_iam_role.eks_node.name
    lambda_exec     = aws_iam_role.lambda_exec.name
    secrets_manager = aws_iam_role.secrets_manager.name
    remediation     = aws_iam_role.remediation.name
  }
  description = "IAM role names for Kubernetes service account annotations (IRSA)"
}

# Secrets Manager ARNs
output "secrets_arns" {
  value = {
    rds_master  = aws_secretsmanager_secret.rds_master.arn
    api_gateway = aws_secretsmanager_secret.api_gateway.arn
    redis_auth  = aws_secretsmanager_secret.redis_auth.arn
  
  }
  description = "Secrets Manager secret ARNs for Week 4 application configuration"
}

output "secrets_names" {
  value = {
    rds_master  = aws_secretsmanager_secret.rds_master.name
    api_gateway = aws_secretsmanager_secret.api_gateway.name
    redis_auth  = aws_secretsmanager_secret.redis_auth.name
    
  }
  description = "Secrets Manager secret names for application reference"
}

# GuardDuty
output "guardduty_detector_id" {
  value       = var.enable_guardduty ? aws_guardduty_detector.main[0].id : null
  description = "GuardDuty detector ID for member account configuration"
}

# Security Hub
output "security_hub_enabled" {
  value       = var.enable_security_hub
  description = "Whether Security Hub is enabled — Week 4 resources should comply with standards"
}

# WAF
output "waf_acl_arn" {
  value       = var.enable_waf ? aws_wafv2_web_acl.main[0].arn : null
  description = "WAF Web ACL ARN — attach to CloudFront distribution in Week 4"
}

output "waf_acl_id" {
  value       = var.enable_waf ? aws_wafv2_web_acl.main[0].id : null
  description = "WAF Web ACL ID for CloudFront association"
}

# SNS Topics
output "sns_topic_arns" {
  value = {
    guardduty_alerts    = var.enable_guardduty ? aws_sns_topic.guardduty_alerts[0].arn : null
    remediation_alerts  = aws_sns_topic.remediation_alerts.arn
  }
  description = "SNS topic ARNs for CloudWatch alarms and notifications in Week 4"
}

# Lambda Functions
output "lambda_function_arns" {
  value = {
    block_public_s3   = aws_lambda_function.block_public_s3.arn
    revoke_unused_iam = aws_lambda_function.revoke_unused_iam.arn
  }
  description = "Lambda function ARNs for EventBridge rules and Security Hub actions"
}

output "lambda_function_names" {
  value = {
    block_public_s3   = aws_lambda_function.block_public_s3.function_name
    revoke_unused_iam = aws_lambda_function.revoke_unused_iam.function_name
  }
  description = "Lambda function names for CloudWatch alarms and dashboards"
}

# CloudWatch Log Groups
output "waf_log_group_arn" {
  value       = var.enable_waf ? aws_cloudwatch_log_group.waf[0].arn : null
  description = "WAF log group ARN for metric filters and dashboards"
}

# Summary
output "week_3_summary" {
  value = {
    kms_keys_created           = 5
    iam_roles_created          = 7
    secrets_created            = 3
    guardduty_enabled          = var.enable_guardduty
    security_hub_enabled       = var.enable_security_hub
    waf_enabled                = var.enable_waf
    remediation_functions      = 2
    sns_topics_created         = var.enable_guardduty ? 2 : 1
    cloudwatch_log_groups      = var.enable_waf ? 1 : 0
  }
  description = "Summary of all Week 3 resources created — useful for cost estimation and documentation"
}