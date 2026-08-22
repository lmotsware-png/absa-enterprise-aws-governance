# ============================================
# ABSA Enterprise AWS - Week 8: Disaster Recovery
# ============================================

variable "primary_region" {
  description = "Primary AWS region (Cape Town)"
  type        = string
  default     = "af-south-1"
}

variable "dr_region" {
  description = "Disaster Recovery region (Ireland)"
  type        = string
  default     = "eu-west-1"
}

variable "environment" {
  description = "Deployment environment identifier"
  type        = string
  default     = "Production"
}

# ============================================
# Route 53 Configuration
# ============================================

variable "domain_name" {
  description = "Root domain for ABSA banking"
  type        = string
  default     = "absa.co.za"
}

variable "failover_ttl" {
  description = "TTL for failover DNS records (seconds)"
  type        = number
  default     = 60
}

# ============================================
# DR EKS Configuration
# ============================================

variable "dr_eks_node_count" {
  description = "Number of nodes in DR EKS (kept minimal until failover)"
  type        = number
  default     = 1
}

# ============================================
# RPO/RTO Configuration
# ============================================

variable "rds_replication_lag_alert_threshold" {
  description = "CloudWatch alarm threshold for replication lag (seconds)"
  type        = number
  default     = 300  # 5 minutes
}

# ============================================
# Cost Toggles
# ============================================

variable "enable_dr_eks" {
  description = "Enable warm standby EKS in DR region (cost)"
  type        = bool
  default     = true
}