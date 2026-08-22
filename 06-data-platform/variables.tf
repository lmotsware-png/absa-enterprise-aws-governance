# ============================================
# ABSA Enterprise AWS - Week 6: Data Platform
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
# Kinesis Configuration
# ============================================

variable "kinesis_stream_name" {
  description = "Name of the Kinesis Data Stream for transactions"
  type        = string
  default     = "absa-transaction-stream"
}

variable "kinesis_shard_count" {
  description = "Number of Kinesis shards (capacity)"
  type        = number
  default     = 4
}

variable "kinesis_retention_hours" {
  description = "How long Kinesis retains records"
  type        = number
  default     = 24
}

variable "firehose_delivery_bucket" {
  description = "S3 bucket name for Firehose delivery"
  type        = string
  default     = "absa-firehose-delivery"
}

# ============================================
# Redshift Configuration
# ============================================

variable "redshift_cluster_name" {
  description = "Name of the Redshift cluster"
  type        = string
  default     = "absa-data-warehouse"
}

variable "redshift_database_name" {
  description = "Redshift database name"
  type        = string
  default     = "absa_analytics"
}

variable "redshift_master_username" {
  description = "Redshift master username"
  type        = string
  default     = "absa_analytics_admin"
}

variable "redshift_node_type" {
  description = "Redshift node instance type"
  type        = string
  default     = "ra3.xlplus"
}

variable "redshift_number_of_nodes" {
  description = "Number of Redshift nodes"
  type        = number
  default     = 2
}

# ============================================
# OpenSearch Configuration
# ============================================

variable "opensearch_domain_name" {
  description = "Name of the OpenSearch domain"
  type        = string
  default     = "absa-logs"
}

variable "opensearch_instance_type" {
  description = "OpenSearch instance type"
  type        = string
  default     = "r6g.large.search"
}

variable "opensearch_instance_count" {
  description = "Number of OpenSearch data nodes"
  type        = number
  default     = 3
}

variable "opensearch_volume_size" {
  description = "EBS volume size per OpenSearch node (GB)"
  type        = number
  default     = 100
}

# ============================================
# Cost-Saving Toggles
# ============================================

variable "enable_redshift" {
  description = "Enable Redshift cluster (expensive)"
  type        = bool
  default     = true
}

variable "enable_opensearch" {
  description = "Enable OpenSearch domain (expensive)"
  type        = bool
  default     = true
}

variable "enable_kinesis_analytics" {
  description = "Enable Kinesis Data Analytics"
  type        = bool
  default     = true
}

#=============================================
#  Athena Configuration
#==============================================

variable "athena_bytes_scanned_limit" {
  description = "Maximum bytes Athena can scan per query — cost control safety net (default: 10GB)"
  type        = number
  default     = 10737418240
}