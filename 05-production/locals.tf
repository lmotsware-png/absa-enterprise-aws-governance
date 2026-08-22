# ============================================
# Local Values — Week 4 Production Layer
# ============================================

locals {
  common_tags = {
    Project     = "ABSA-Enterprise-AWS"
    CostCenter  = "Cloud-Production"
    DataClass   = "Confidential"
    ManagedBy   = "Terraform"
  }

  # Subnet Selection — From Week 2
  vpc_id              = data.terraform_remote_state.networking.outputs.vpc_ids.production
  public_subnet_ids   = data.terraform_remote_state.networking.outputs.subnet_ids.production_public
  app_subnet_ids      = data.terraform_remote_state.networking.outputs.subnet_ids.production_app
  data_subnet_ids     = data.terraform_remote_state.networking.outputs.subnet_ids.production_data
  endpoint_subnet_ids = data.terraform_remote_state.networking.outputs.subnet_ids.production_endpoints

  # Security Groups — From Week 2
  alb_security_group_id      = data.terraform_remote_state.networking.outputs.security_group_ids.alb
  app_security_group_id      = data.terraform_remote_state.networking.outputs.security_group_ids.baseline_app
  data_security_group_id     = data.terraform_remote_state.networking.outputs.security_group_ids.baseline_data
  endpoint_security_group_id = data.terraform_remote_state.networking.outputs.security_group_ids.vpc_endpoints

  # IAM Roles — From Week 3
  eks_cluster_role_arn = data.terraform_remote_state.security.outputs.iam_role_arns.eks_cluster
  eks_node_role_arn    = data.terraform_remote_state.security.outputs.iam_role_arns.eks_node

  # KMS Keys — From Week 3
  kms_rds_arn     = data.terraform_remote_state.security.outputs.kms_key_arns.rds
  kms_s3_arn      = data.terraform_remote_state.security.outputs.kms_key_arns.s3
  kms_secrets_arn = data.terraform_remote_state.security.outputs.kms_key_arns.secrets
  kms_lambda_arn  = data.terraform_remote_state.security.outputs.kms_key_arns.lambda
  kms_eks_arn    = data.terraform_remote_state.security.outputs.kms_key_arns.eks 
  kms_ebs_arn     = data.terraform_remote_state.security.outputs.kms_key_arns.ebs

  # Secrets — From Week 3
  rds_secret_arn   = data.terraform_remote_state.security.outputs.secrets_arns.rds_master
  redis_secret_arn = data.terraform_remote_state.security.outputs.secrets_arns.redis_auth
  api_secret_arn   = data.terraform_remote_state.security.outputs.secrets_arns.api_gateway
  cloudfront_verify_secret_arn = data.terraform_remote_state.security.outputs.secrets_arns.cloudfront_verify

  # WAF — From Week 3
  waf_acl_arn = data.terraform_remote_state.security.outputs.waf_acl_arn

  # EKS Add-ons
  eks_addons = {
    vpc_cni    = "vpc-cni"
    coredns    = "coredns"
    kube_proxy = "kube-proxy"
  }

  # Kubernetes Namespaces
  namespaces = [
    "payment-api",
    "fraud-detection",
    "notification-service",
    "compliance-audit",
    "monitoring",
    "data-platform"
  ]

  # Connection Strings
  rds_connection_string   = "postgresql://${var.rds_master_username}:<password>@${aws_rds_cluster.main.endpoint}:${var.rds_port}/${var.rds_database_name}"
  redis_connection_string = "redis://:${var.redis_port}@${aws_elasticache_replication_group.main.primary_endpoint_address}:${var.redis_port}"
}