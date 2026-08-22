variable "primary_region" {
  description = "Primary AWS region for ABSA operations"
  type        = string
  default     = "eu-west-1"
}

variable "environment" {
  description = "Deployment environment identifier"
  type        = string
  default     = "Production"
}

variable "kms_deletion_window" {
  description = "Days before KMS key is permanently deleted after being marked for deletion"
  type        = number
  default     = 30
}

variable "enable_guardduty" {
  description = "Enable Amazon GuardDuty threat detection"
  type        = bool
  default     = true
}

variable "enable_security_hub" {
  description = "Enable AWS Security Hub central dashboard"
  type        = bool
  default     = true
}

variable "enable_waf" {
  description = "Enable AWS WAF for web application protection"
  type        = bool
  default     = true
}

variable "guardduty_finding_publishing_frequency" {
  description = "How often GuardDuty publishes findings"
  type        = string
  default     = "FIFTEEN_MINUTES"
}

variable "security_hub_standards" {
  description = "Security standards to enable in Security Hub"
  type = list(string)
  default = [
    "aws-foundational-security-best-practices/v/1.0.0",
    "cis-aws-foundations-benchmark/v/1.4.0",
    "pci-dss/v/3.2.1"
  ]
}

variable "lambda_remediation_functions" {
  description = "Auto-remediation Lambda functions to deploy"
  type = map(object({
    description = string
    runtime     = string
    handler     = string
    timeout     = number
  }))
  default = {
    block_public_s3 = {
      description = "Automatically blocks public S3 buckets"
      runtime     = "python3.12"
      handler     = "index.handler"
      timeout     = 30
    }
    revoke_unused_iam = {
      description = "Revokes unused IAM access keys older than 90 days"
      runtime     = "python3.12"
      handler     = "index.handler"
      timeout     = 60
    }
  }
}