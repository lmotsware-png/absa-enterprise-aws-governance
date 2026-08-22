# ============================================
# SQS Queues — Decoupled Microservice Communication
# ============================================

# ============================================
# DEAD LETTER QUEUES (Created first — referenced by main queues)
# ============================================

resource "aws_sqs_queue" "dlq_fraud" {
  name                       = local.queue_names.dlq_fraud
  delay_seconds              = 0
  max_message_size           = var.sqs_max_message_size
  message_retention_seconds  = var.sqs_dlq_retention_days * 86400
  receive_wait_time_seconds  = var.sqs_dlq_receive_wait_seconds

  kms_master_key_id                 = local.kms_s3_arn
  kms_data_key_reuse_period_seconds = var.sqs_kms_key_reuse_seconds

  tags = merge(local.common_tags, {
    Name = local.queue_names.dlq_fraud
    Type = "Dead-Letter-Queue"
  })
}

resource "aws_sqs_queue" "dlq_audit" {
  name                       = local.queue_names.dlq_audit
  delay_seconds              = 0
  max_message_size           = var.sqs_max_message_size
  message_retention_seconds  = var.sqs_dlq_retention_days * 86400
  receive_wait_time_seconds  = var.sqs_dlq_receive_wait_seconds

  kms_master_key_id                 = local.kms_s3_arn
  kms_data_key_reuse_period_seconds = var.sqs_kms_key_reuse_seconds

  tags = merge(local.common_tags, {
    Name = local.queue_names.dlq_audit
    Type = "Dead-Letter-Queue"
  })
}

resource "aws_sqs_queue" "dlq_notification" {
  name                       = local.queue_names.dlq_notification
  delay_seconds              = 0
  max_message_size           = var.sqs_max_message_size
  message_retention_seconds  = var.sqs_dlq_retention_days * 86400
  receive_wait_time_seconds  = var.sqs_dlq_receive_wait_seconds

  kms_master_key_id                 = local.kms_s3_arn
  kms_data_key_reuse_period_seconds = var.sqs_kms_key_reuse_seconds

  tags = merge(local.common_tags, {
    Name = local.queue_names.dlq_notification
    Type = "Dead-Letter-Queue"
  })
}

resource "aws_sqs_queue" "dlq_payment" {
  name                       = local.queue_names.dlq_payment
  delay_seconds              = 0
  max_message_size           = var.sqs_max_message_size
  message_retention_seconds  = var.sqs_dlq_retention_days * 86400
  receive_wait_time_seconds  = var.sqs_dlq_receive_wait_seconds

  kms_master_key_id                 = local.kms_s3_arn
  kms_data_key_reuse_period_seconds = var.sqs_kms_key_reuse_seconds

  tags = merge(local.common_tags, {
    Name = local.queue_names.dlq_payment
    Type = "Dead-Letter-Queue"
  })
}

# ============================================
# MAIN QUEUES — With redrive policy to DLQ
# ============================================

resource "aws_sqs_queue" "fraud_detection" {
  name                       = local.queue_names.fraud_detection
  delay_seconds              = var.sqs_delay_seconds
  max_message_size           = var.sqs_max_message_size
  message_retention_seconds  = var.sqs_message_retention_days * 86400
  receive_wait_time_seconds  = var.sqs_receive_wait_seconds
  visibility_timeout_seconds = var.sqs_visibility_timeout

  kms_master_key_id                 = local.kms_s3_arn
  kms_data_key_reuse_period_seconds = var.sqs_kms_key_reuse_seconds

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq_fraud.arn
    maxReceiveCount     = var.sqs_max_receive_count
  })

  tags = merge(local.common_tags, {
    Name = local.queue_names.fraud_detection
    Type = "Main-Queue"
  })
}

resource "aws_sqs_queue" "audit_logging" {
  name                       = local.queue_names.audit_logging
  delay_seconds              = var.sqs_delay_seconds
  max_message_size           = var.sqs_max_message_size
  message_retention_seconds  = var.sqs_message_retention_days * 86400
  receive_wait_time_seconds  = var.sqs_receive_wait_seconds
  visibility_timeout_seconds = var.sqs_visibility_timeout

  kms_master_key_id                 = local.kms_s3_arn
  kms_data_key_reuse_period_seconds = var.sqs_kms_key_reuse_seconds

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq_audit.arn
    maxReceiveCount     = var.sqs_max_receive_count
  })

  tags = merge(local.common_tags, {
    Name = local.queue_names.audit_logging
    Type = "Main-Queue"
  })
}

resource "aws_sqs_queue" "notification" {
  name                       = local.queue_names.notification
  delay_seconds              = var.sqs_delay_seconds
  max_message_size           = var.sqs_max_message_size
  message_retention_seconds  = var.sqs_message_retention_days * 86400
  receive_wait_time_seconds  = var.sqs_receive_wait_seconds
  visibility_timeout_seconds = var.sqs_visibility_timeout

  kms_master_key_id                 = local.kms_s3_arn
  kms_data_key_reuse_period_seconds = var.sqs_kms_key_reuse_seconds

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq_notification.arn
    maxReceiveCount     = var.sqs_max_receive_count
  })

  tags = merge(local.common_tags, {
    Name = local.queue_names.notification
    Type = "Main-Queue"
  })
}

resource "aws_sqs_queue" "payment_events" {
  name                       = local.queue_names.payment_events
  delay_seconds              = var.sqs_delay_seconds
  max_message_size           = var.sqs_max_message_size
  message_retention_seconds  = var.sqs_message_retention_days * 86400
  receive_wait_time_seconds  = var.sqs_receive_wait_seconds
  visibility_timeout_seconds = var.sqs_visibility_timeout

  kms_master_key_id                 = local.kms_s3_arn
  kms_data_key_reuse_period_seconds = var.sqs_kms_key_reuse_seconds

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq_payment.arn
    maxReceiveCount     = var.sqs_max_receive_count
  })

  tags = merge(local.common_tags, {
    Name = local.queue_names.payment_events
    Type = "Main-Queue"
  })
}