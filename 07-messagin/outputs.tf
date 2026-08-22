# ============================================
# Outputs — Values for Weeks 8 and 9
# ============================================

output "fraud_detection_queue_url" {
  value       = aws_sqs_queue.fraud_detection.url
  description = "Fraud detection queue URL"
}

output "audit_logging_queue_url" {
  value       = aws_sqs_queue.audit_logging.url
  description = "Audit logging queue URL"
}

output "notification_queue_url" {
  value       = aws_sqs_queue.notification.url
  description = "Notification queue URL"
}

output "payment_events_topic_arn" {
  value       = aws_sns_topic.payment_events.arn
  description = "Payment events SNS topic ARN"
}

output "fraud_alerts_topic_arn" {
  value       = aws_sns_topic.fraud_alerts.arn
  description = "Fraud alerts SNS topic ARN"
}

output "mq_broker_endpoint" {
  value       = var.enable_amazon_mq ? aws_mq_broker.legacy_integration[0].instances[0].endpoints[0] : null
  description = "Amazon MQ broker endpoint for legacy integration"
}

output "week_7_summary" {
  value = {
    sqs_queues_created      = 8
    sns_topics_created      = 3
    sns_subscriptions       = 4
    amazon_mq_enabled       = var.enable_amazon_mq
    dead_letter_queues      = 4
    messages_encrypted      = true
  }
  description = "Summary of all Week 7 messaging resources"
}