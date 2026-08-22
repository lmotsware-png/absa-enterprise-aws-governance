variable "primary_region" {
  description = "Primary AWS region for ABSA operations"
  type        = string
  default     = "af-south-1"
}

variable "environment" {
  description = "Deployment environment identifier"
  type        = string
  default     = "Management"
}

variable "log_retention_days" {
  description = "Number of days to retain CloudTrail and Config logs"
  type        = number
  default     = 365
}

variable "s3_log_archive_retention_days" {
  description = "Number of days before S3 logs transition to Glacier"
  type        = number
  default     = 90
}

variable "s3_log_archive_glacier_retention_days" {
  description = "Number of days before Glacier logs are permanently deleted"
  type        = number
  default     = 2555  # 7 years total (90 + 2555 = 2645 days)
}

variable "config_recording_frequency" {
  description = "How often AWS Config records resource changes"
  type        = string
  default     = "CONTINUOUS"
}

variable "enable_vpc_flow_logs" {
  description = "Enable VPC Flow Logs for all VPCs"
  type        = bool
  default     = true
}

variable "flow_logs_transition_days" {
  description = "Days before VPC Flow Logs transition to Glacier"
  type        = number
  default     = 30
}

variable "flow_logs_expiration_days" {
  description = "Days before VPC Flow Logs are permanently deleted"
  type        = number
  default     = 365
}