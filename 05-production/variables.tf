# ============================================
# ABSA Enterprise AWS - Week 4: Production Layer
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
# EKS Cluster Configuration
# ============================================

variable "eks_cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "ABSA-Production-EKS"
}

variable "eks_cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.36"
}

variable "eks_node_instance_types" {
  description = "EC2 instance types for EKS worker nodes"
  type        = list(string)
  default     = ["c6i.xlarge", "c6i.2xlarge"]
}

variable "eks_node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 3
}

variable "eks_node_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 2
}

variable "eks_node_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 10
}

variable "eks_node_disk_size" {
  description = "Disk size in GB for worker nodes"
  type        = number
  default     = 100
}

# ============================================
# RDS Aurora Configuration
# ============================================

variable "rds_cluster_name" {
  description = "Name of the RDS Aurora cluster"
  type        = string
  default     = "absa-production-aurora"
}

variable "rds_engine" {
  description = "Aurora database engine"
  type        = string
  default     = "aurora-postgresql"
}

variable "rds_engine_version" {
  description = "Aurora PostgreSQL version"
  type        = string
  default     = "16.4"
}

variable "rds_instance_class" {
  description = "Instance class for Aurora instances"
  type        = string
  default     = "db.r6g.large"
}

variable "rds_database_name" {
  description = "Name of the initial database"
  type        = string
  default     = "absa_banking"
}

variable "rds_master_username" {
  description = "Master username for the database"
  type        = string
  default     = "absa_admin"
}

variable "rds_port" {
  description = "Port for the database"
  type        = number
  default     = 5432
}

variable "rds_backup_retention_days" {
  description = "Number of days to retain automated backups"
  type        = number
  default     = 30
}

variable "rds_deletion_protection" {
  description = "Prevent accidental deletion of the database"
  type        = bool
  default     = true
}

# ============================================
# ElastiCache Redis Configuration
# ============================================

variable "redis_cluster_name" {
  description = "Name of the Redis cluster"
  type        = string
  default     = "absa-production-redis"
}
variable "redis_engine_version" {
  description = "Redis engine version"
  type        = string
  default     = "7.1"
}


variable "redis_node_type" {
  description = "Instance type for Redis nodes"
  type        = string
  default     = "cache.r6g.large"
}

variable "redis_num_cache_nodes" {
  description = "Number of Redis nodes"
  type        = number
  default     = 2
}

variable "redis_port" {
  description = "Port for Redis"
  type        = number
  default     = 6379
}

# ============================================
# API Gateway Configuration
# ============================================

variable "api_gateway_name" {
  description = "Name of the API Gateway"
  type        = string
  default     = "ABSA-Banking-API"
}

variable "api_gateway_stage" {
  description = "Deployment stage for API Gateway"
  type        = string
  default     = "prod"
}

# ============================================
# CloudFront Configuration
# ============================================

variable "cloudfront_domain_name" {
  description = "Custom domain for CloudFront distribution"
  type        = string
  default     = "banking.absa.co.za"
}

variable "cloudfront_price_class" {
  description = "CloudFront price class"
  type        = string
  default     = "PriceClass_100"
}

# ============================================
# Cost-Saving Toggles
# ============================================

variable "enable_multi_az_rds" {
  description = "Enable Multi-AZ deployment for RDS"
  type        = bool
  default     = true
}

variable "enable_redis_multi_az" {
  description = "Enable Multi-AZ for Redis"
  type        = bool
  default     = true
}

variable "enable_cloudfront" {
  description = "Create CloudFront distribution"
  type        = bool
  default     = true
}