# ============================================
# Outputs — Week 5 Production
# Consumed by: Week 6, Week 7, Week 8, Week 9
# ============================================

# ============================================
# EKS Cluster
# ============================================

output "eks_cluster_name" {
  value       = aws_eks_cluster.main.name
  description = "EKS cluster name — used by Week 8 DR naming and Week 9 CodeBuild deploy"
}

output "eks_cluster_endpoint" {
  value       = aws_eks_cluster.main.endpoint
  description = "EKS cluster API endpoint — used by Week 9 CodeBuild kubeconfig generation"
}

output "eks_cluster_arn" {
  value       = aws_eks_cluster.main.arn
  description = "EKS cluster ARN for IAM policies"
}

output "eks_oidc_issuer" {
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
  description = "EKS OIDC issuer URL for IRSA configuration"
}

output "eks_oidc_provider_arn" {
  value       = aws_iam_openid_connect_provider.eks.arn
  description = "EKS OIDC provider ARN — used by Week 8 DR IRSA and Week 9 CodeBuild"
}

# ============================================
# EKS Node Group
# ============================================

output "eks_node_group_name" {
  value       = aws_eks_node_group.payment_workers.node_group_name
  description = "EKS node group name for monitoring"
}

output "eks_node_group_arn" {
  value       = aws_eks_node_group.payment_workers.arn
  description = "EKS node group ARN for IAM policies"
}

# ============================================
# ADDED: eks_node_role_arn
# ============================================
# Required by:
#   Week 9 ecr_repositories.tf — Statement 2 "AllowEKSNodePull"
#   grants this role permission to pull images from ECR.
#   Without this, EKS nodes cannot pull application
#   container images and every pod fails with ErrImagePull.
#
# The node role is attached to the EC2 instance profile
# that runs on every EKS worker node. When kubelet calls
# ECR to pull an image for a new pod, it authenticates
# using this role's credentials.

output "eks_node_role_arn" {
  value       = aws_iam_role.eks_nodes.arn
  description = "EKS worker node IAM role ARN — used by Week 9 ECR repository pull policy"
}

# ============================================
# RDS Aurora
# ============================================

output "rds_cluster_endpoint" {
  value       = aws_rds_cluster.main.endpoint
  description = "RDS Aurora writer endpoint — used by Week 8 Route53 health check monitoring"
}

output "rds_cluster_reader_endpoint" {
  value       = aws_rds_cluster.main.reader_endpoint
  description = "RDS Aurora reader endpoint — used by Week 9 CodeBuild integration tests"
}

output "rds_cluster_arn" {
  value       = aws_rds_cluster.main.arn
  description = "RDS Aurora cluster ARN for IAM policies and monitoring"
}

output "rds_cluster_id" {
  value       = aws_rds_cluster.main.cluster_identifier
  description = "RDS Aurora cluster identifier — used by Week 8 cross-region replica source"
}

output "rds_database_name" {
  value       = var.rds_database_name
  description = "Database name for application configuration"
}

output "rds_port" {
  value       = var.rds_port
  description = "Database port for connection strings"
}

# ============================================
# ElastiCache Redis
# ============================================

output "redis_primary_endpoint" {
  value       = aws_elasticache_replication_group.main.primary_endpoint_address
  description = "Redis primary endpoint for application connection"
}

output "redis_reader_endpoint" {
  value       = aws_elasticache_replication_group.main.reader_endpoint_address
  description = "Redis reader endpoint for read-only operations"
}

output "redis_port" {
  value       = var.redis_port
  description = "Redis port for connection strings"
}

output "redis_cluster_id" {
  value       = aws_elasticache_replication_group.main.replication_group_id
  description = "Redis replication group ID for monitoring"
}

# ============================================
# API Gateway
# ============================================

output "api_gateway_id" {
  value       = aws_api_gateway_rest_api.main.id
  description = "API Gateway REST API ID for integrations"
}

output "api_gateway_endpoint" {
  value       = "${aws_api_gateway_rest_api.main.id}.execute-api.${var.primary_region}.amazonaws.com"
  description = "API Gateway invoke URL — used by Week 8 Route53 primary health check"
}

output "api_gateway_stage" {
  value       = aws_api_gateway_stage.main.stage_name
  description = "API Gateway stage name"
}

# ============================================
# Application Load Balancer
# ============================================

output "alb_dns_name" {
  value       = aws_lb.main.dns_name
  description = "ALB DNS name for DNS records and health checks"
}

output "alb_arn" {
  value       = aws_lb.main.arn
  description = "ALB ARN for WAF association and monitoring"
}

output "alb_target_group_arn" {
  value       = aws_lb_target_group.payment_api.arn
  description = "ALB target group ARN for EKS service configuration"
}

# ============================================
# CloudFront
# ============================================

output "cloudfront_domain_name" {
  value       = var.enable_cloudfront ? aws_cloudfront_distribution.main[0].domain_name : null
  description = "CloudFront domain name — used by Week 8 Route53 PRIMARY failover record alias"
}

output "cloudfront_distribution_id" {
  value       = var.enable_cloudfront ? aws_cloudfront_distribution.main[0].id : null
  description = "CloudFront distribution ID for invalidation and monitoring"
}

# ============================================
# Kubernetes
# ============================================

output "kubernetes_namespaces" {
  value       = local.namespaces
  description = "Kubernetes namespaces created in Week 5"
}

# ============================================
# Consolidated Connection Info
# ============================================

output "connection_info" {
  value = {
    rds_endpoint   = aws_rds_cluster.main.endpoint
    rds_port       = var.rds_port
    redis_endpoint = aws_elasticache_replication_group.main.primary_endpoint_address
    redis_port     = var.redis_port
    api_endpoint   = "${aws_api_gateway_rest_api.main.id}.execute-api.${var.primary_region}.amazonaws.com/${var.api_gateway_stage}"
  }
  description = "Consolidated connection info — used by Week 8 DR connection_info and Week 9 integration tests"
  sensitive   = false
}

# ============================================
# Week 5 Summary
# ============================================

output "week_5_summary" {
  value = {
    eks_cluster_created   = true
    eks_nodes             = var.eks_node_desired_size
    rds_engine            = var.rds_engine
    rds_multi_az          = var.enable_multi_az_rds
    redis_nodes           = var.redis_num_cache_nodes
    redis_multi_az        = var.enable_redis_multi_az
    api_gateway_endpoints = 2
    cloudfront_enabled    = var.enable_cloudfront
    namespaces_created    = length(local.namespaces)
    irsa_roles_created    = 1
  }
  description = "Summary of all Week 5 production resources"
}