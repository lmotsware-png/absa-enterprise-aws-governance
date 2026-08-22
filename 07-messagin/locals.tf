locals {
  common_tags = {
    Project     = "ABSA-Enterprise-AWS"
    CostCenter  = "Cloud-Messaging"
    DataClass   = "Internal"
    ManagedBy   = "Terraform"
  }

  # KMS key from Week 3
  kms_s3_arn = data.terraform_remote_state.security.outputs.kms_key_arns.s3

  # VPC and subnet info from Week 2
  vpc_id         = data.terraform_remote_state.networking.outputs.vpc_ids.production
  app_subnet_ids = data.terraform_remote_state.networking.outputs.subnet_ids.production_app
  data_subnet_ids = data.terraform_remote_state.networking.outputs.subnet_ids.production_data

  # Security group from Week 2
  app_security_group_id = data.terraform_remote_state.networking.outputs.security_group_ids.baseline_app

  # Kinesis stream from Week 6 (for audit events)
  kinesis_stream_arn = data.terraform_remote_state.data_platform.outputs.kinesis_stream_arn

  # Queue names — single source of truth
  queue_names = {
    fraud_detection  = "absa-fraud-detection-queue"
    audit_logging    = "absa-audit-logging-queue"
    notification     = "absa-notification-queue"
    payment_events   = "absa-payment-events-queue"
    dlq_fraud        = "absa-fraud-detection-dlq"
    dlq_audit        = "absa-audit-logging-dlq"
    dlq_notification = "absa-notification-dlq"
    dlq_payment      = "absa-payment-events-dlq"
  }

  # SNS topic names
  sns_topic_names = {
    payment_events  = "ABSA-Payment-Events"
    fraud_alerts    = "ABSA-Fraud-Alerts"
    system_notifications = "ABSA-System-Notifications"
  }
}

data "aws_caller_identity" "current" {}