locals {
  common_tags = {
    Project     = "ABSA-Enterprise-AWS"
    CostCenter  = "Cloud-Analytics"
    DataClass   = "Confidential"
    ManagedBy   = "Terraform"
  }

  # VPC and subnet info from Week 2
  vpc_id         = data.terraform_remote_state.networking.outputs.vpc_ids.production
  app_subnet_ids = data.terraform_remote_state.networking.outputs.subnet_ids.production_app
  data_subnet_ids = data.terraform_remote_state.networking.outputs.subnet_ids.production_data

  # App subnet CIDRs for OpenSearch access policy
  app_subnet_cidrs = [
    "10.1.11.0/24",
    "10.1.12.0/24",
    "10.1.13.0/24"
  ]

  # Security group from Week 2
  data_security_group_id = data.terraform_remote_state.networking.outputs.security_group_ids.baseline_data

  # KMS keys from Week 3
  kms_s3_arn = data.terraform_remote_state.security.outputs.kms_key_arns.s3

  # S3 buckets from Week 4 (for Athena to query)
  cloudtrail_bucket_name = data.terraform_remote_state.shared_services.outputs.cloudtrail_bucket_name
  config_bucket_name     = data.terraform_remote_state.shared_services.outputs.config_bucket_name
  flow_logs_bucket_name  = data.terraform_remote_state.shared_services.outputs.flow_logs_bucket_name

  # Production endpoints from Week 5
  rds_endpoint = data.terraform_remote_state.production.outputs.rds_cluster_endpoint

  # S3 bucket names for the data platform
  firehose_bucket_name  = "${var.firehose_delivery_bucket}-${data.aws_caller_identity.current.account_id}"
  athena_results_bucket = "absa-athena-results-${data.aws_caller_identity.current.account_id}"
}

data "aws_caller_identity" "current" {}