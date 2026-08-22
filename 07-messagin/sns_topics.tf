# ============================================
# SNS Topics — Fan-Out Notifications
# ============================================

# Payment Events Topic — Fans out to fraud, audit, and notification queues
resource "aws_sns_topic" "payment_events" {
  name              = local.sns_topic_names.payment_events
  kms_master_key_id = local.kms_s3_arn

  tags = merge(local.common_tags, {
    Name = local.sns_topic_names.payment_events
  })
}

# Fraud Alerts Topic — Notifies security team of high-risk transactions
resource "aws_sns_topic" "fraud_alerts" {
  name              = local.sns_topic_names.fraud_alerts
  kms_master_key_id = local.kms_s3_arn

  tags = merge(local.common_tags, {
    Name = local.sns_topic_names.fraud_alerts
  })
}

# System Notifications Topic — Operational alerts
resource "aws_sns_topic" "system_notifications" {
  name              = local.sns_topic_names.system_notifications
  kms_master_key_id = local.kms_s3_arn

  tags = merge(local.common_tags, {
    Name = local.sns_topic_names.system_notifications
  })
}

# ============================================
# SNS to SQS Subscriptions — Connect topics to queues
# ============================================

resource "aws_sns_topic_subscription" "payment_to_fraud" {
  topic_arn = aws_sns_topic.payment_events.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.fraud_detection.arn
}

resource "aws_sns_topic_subscription" "payment_to_audit" {
  topic_arn = aws_sns_topic.payment_events.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.audit_logging.arn
}

resource "aws_sns_topic_subscription" "payment_to_notification" {
  topic_arn = aws_sns_topic.payment_events.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.notification.arn
}

resource "aws_sns_topic_subscription" "payment_to_events" {
  topic_arn = aws_sns_topic.payment_events.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.payment_events.arn
}