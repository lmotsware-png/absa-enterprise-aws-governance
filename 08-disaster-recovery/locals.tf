locals {
  common_tags = {
    Project     = "ABSA-Enterprise-AWS"
    CostCenter  = "Cloud-DR"
    DataClass   = "Confidential"
    ManagedBy   = "Terraform"
  }

  primary_vpc_cidr      = "10.1.0.0/16"
  dr_vpc_cidr           = "10.101.0.0/16"
  dr_public_subnets     = ["10.101.1.0/24", "10.101.2.0/24", "10.101.3.0/24"]
  dr_app_subnets        = ["10.101.11.0/24", "10.101.12.0/24", "10.101.13.0/24"]
  dr_data_subnets       = ["10.101.21.0/24", "10.101.22.0/24", "10.101.23.0/24"]
  dr_availability_zones = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]

  # KMS keys from Week 3
  kms_rds_arn = data.terraform_remote_state.security.outputs.kms_key_arns.rds
  kms_s3_arn  = data.terraform_remote_state.security.outputs.kms_key_arns.s3

  # WAF from Week 3 — scope = CLOUDFRONT, attaches to DR CloudFront
  waf_acl_arn = data.terraform_remote_state.security.outputs.waf_acl_arn

  # Primary RDS from Week 5
  primary_rds_endpoint     = data.terraform_remote_state.production.outputs.rds_cluster_endpoint
  primary_rds_cluster_id   = data.terraform_remote_state.production.outputs.rds_cluster_id

  # Primary EKS from Week 5
  primary_eks_cluster_name = data.terraform_remote_state.production.outputs.eks_cluster_name

  # CloudTrail and Config buckets from Week 4
  cloudtrail_bucket_name = data.terraform_remote_state.shared_services.outputs.cloudtrail_bucket_name
  cloudtrail_bucket_arn  = data.terraform_remote_state.shared_services.outputs.cloudtrail_bucket_arn
  config_bucket_name     = data.terraform_remote_state.shared_services.outputs.config_bucket_name
  config_bucket_arn      = data.terraform_remote_state.shared_services.outputs.config_bucket_arn

  # Primary API Gateway endpoint from Week 5 — monitored by Route 53 health check
  primary_api_endpoint = data.terraform_remote_state.production.outputs.api_gateway_endpoint

  # Primary CloudFront domain from Week 5 — target for PRIMARY failover record
  primary_cloudfront_domain = data.terraform_remote_state.production.outputs.cloudfront_domain_name
}

data "aws_caller_identity" "current" {}