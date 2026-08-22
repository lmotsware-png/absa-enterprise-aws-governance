# ============================================
# ABSA Enterprise AWS - Week 7: Messaging
# ============================================

variable "primary_region" {
  description = "Primary AWS region for ABSA operations"
  type        = string
  default     = "af-south-1"
}

variable "environment" {
  description = "Deployment environment identifier"
  type        = string
  default     = "Production"
}

# ============================================
# SQS Configuration — Main Queues
# ============================================

variable "sqs_visibility_timeout" {
  description = "How long a message is hidden after being received (seconds)"
  type        = number
  default     = 30
}

variable "sqs_max_receive_count" {
  description = "Number of receives before message goes to DLQ"
  type        = number
  default     = 3
}

variable "sqs_delay_seconds" {
  description = "Delay before message is available to consumers"
  type        = number
  default     = 0
}

variable "sqs_message_retention_days" {
  description = "Days to retain messages in main queues"
  type        = number
  default     = 4
}

variable "sqs_max_message_size" {
  description = "Maximum message size in bytes (256KB = 262144)"
  type        = number
  default     = 262144
}

variable "sqs_receive_wait_seconds" {
  description = "Long polling wait time for main queues — reduces empty responses and API costs"
  type        = number
  default     = 20
}

# ============================================
# SQS Configuration — Dead Letter Queues
# ============================================

variable "sqs_dlq_retention_days" {
  description = "Days to retain messages in DLQs before deletion — operations investigates during this window"
  type        = number
  default     = 14
}

variable "sqs_dlq_receive_wait_seconds" {
  description = "Long polling wait time for DLQs — DLQ consumers poll at human/automated pace"
  type        = number
  default     = 10
}

# ============================================
# SQS Configuration — KMS Encryption
# ============================================

variable "sqs_kms_key_reuse_seconds" {
  description = "Seconds before KMS data key is rotated for SQS — reduces KMS API call costs"
  type        = number
  default     = 300
}

# ============================================
# Amazon MQ Configuration
# ============================================

variable "enable_amazon_mq" {
  description = "Enable Amazon MQ for legacy system integration"
  type        = bool
  default     = true
}

variable "mq_broker_name" {
  description = "Name of the Amazon MQ broker"
  type        = string
  default     = "absa-legacy-integration"
}

variable "mq_engine_type" {
  description = "Amazon MQ broker engine type"
  type        = string
  default     = "ActiveMQ"
}

variable "mq_engine_version" {
  description = "Amazon MQ engine version"
  type        = string
  default     = "5.17.6"
}

variable "mq_instance_type" {
  description = "Amazon MQ instance type"
  type        = string
  default     = "mq.m5.large"
}

variable "mq_username" {
  description = "Amazon MQ master username"
  type        = string
  default     = "absa_mq_admin"
}