# ============================================
# Outputs — Week 8 Disaster Recovery
# ============================================
#
# This file exports values from all Week 8 DR resources.
# Consumers of these outputs:
#   - Week 9 (if added) — operational runbooks, automation
#   - DR activation scripts — failover procedures
#   - Monitoring systems — external health checks
#   - README.md — human-readable DR reference
#
# Output categories:
#   1. DR VPC and networking (dr_vpc.tf)
#   2. DR RDS cross-region replica (rds_cross_region.tf)
#   3. DR S3 replication (s3_cross_region.tf)
#   4. DR EKS warm standby (eks_warm_standby.tf)
#   5. DR DNS failover (route53_failover.tf)
#   6. DR health monitoring (dr_health_checks.tf)
#   7. Week 8 summary
# ============================================

# ============================================
# SECTION 1 — DR VPC and Networking
# ============================================

output "dr_vpc_id" {
  value       = aws_vpc.dr.id
  description = "DR VPC ID in eu-west-1"
}

output "dr_vpc_cidr" {
  value       = aws_vpc.dr.cidr_block
  description = "DR VPC CIDR block — 10.101.0.0/16"
}

output "dr_public_subnet_ids" {
  value       = aws_subnet.dr_public[*].id
  description = "DR public subnet IDs across eu-west-1a/b/c"
}

output "dr_app_subnet_ids" {
  value       = aws_subnet.dr_app[*].id
  description = "DR application tier subnet IDs across eu-west-1a/b/c"
}

output "dr_data_subnet_ids" {
  value       = aws_subnet.dr_data[*].id
  description = "DR data tier subnet IDs across eu-west-1a/b/c"
}

output "dr_security_group_ids" {
  value = {
    public = aws_security_group.dr_public.id
    app    = aws_security_group.dr_app.id
    data   = aws_security_group.dr_data.id
  }
  description = "DR security group IDs — public/app/data tier"
}

output "dr_nat_gateway_ids" {
  value       = aws_nat_gateway.dr[*].id
  description = "DR NAT Gateway IDs — one per AZ in eu-west-1"
}

output "dr_nat_gateway_public_ips" {
  value       = aws_eip.dr_nat[*].public_ip
  description = "DR NAT Gateway public IPs — allowlist these in external firewall rules during failover"
}

# ============================================
# SECTION 2 — DR KMS Keys
# ============================================

output "dr_kms_key_arns" {
  value = {
    rds = aws_kms_key.dr_rds.arn
    s3  = aws_kms_key.dr_s3.arn
    eks = aws_kms_key.dr_eks.arn
  }
  description = "All DR KMS key ARNs in eu-west-1 — rds/s3/eks"
}

output "dr_kms_key_aliases" {
  value = {
    rds = aws_kms_alias.dr_rds.name
    s3  = aws_kms_alias.dr_s3.name
    eks = aws_kms_alias.dr_eks.name
  }
  description = "All DR KMS key aliases in eu-west-1"
}

# ============================================
# SECTION 3 — DR RDS Cross-Region Replica
# ============================================

output "dr_rds_cluster_endpoint" {
  value       = aws_rds_cluster.dr.endpoint
  description = "DR Aurora cluster writer endpoint — becomes primary after failover promotion"
}

output "dr_rds_cluster_reader_endpoint" {
  value       = aws_rds_cluster.dr.reader_endpoint
  description = "DR Aurora cluster reader endpoint"
}

output "dr_rds_cluster_id" {
  value       = aws_rds_cluster.dr.cluster_identifier
  description = "DR Aurora cluster identifier — absa-dr-aurora"
}

output "dr_rds_cluster_arn" {
  value       = aws_rds_cluster.dr.arn
  description = "DR Aurora cluster ARN"
}

output "dr_rds_database_name" {
  value       = aws_rds_cluster.dr.database_name
  description = "DR Aurora database name"
}

output "dr_rds_port" {
  value       = aws_rds_cluster.dr.port
  description = "DR Aurora cluster port — 5432 for PostgreSQL"
}

# ============================================
# SECTION 4 — DR S3 Buckets and Replication
# ============================================

output "dr_cloudtrail_bucket_name" {
  value       = aws_s3_bucket.dr_cloudtrail.id
  description = "DR CloudTrail logs S3 bucket name in eu-west-1"
}

output "dr_cloudtrail_bucket_arn" {
  value       = aws_s3_bucket.dr_cloudtrail.arn
  description = "DR CloudTrail logs S3 bucket ARN"
}

output "dr_config_bucket_name" {
  value       = aws_s3_bucket.dr_config.id
  description = "DR Config logs S3 bucket name in eu-west-1"
}

output "dr_config_bucket_arn" {
  value       = aws_s3_bucket.dr_config.arn
  description = "DR Config logs S3 bucket ARN"
}

output "s3_replication_role_arn" {
  value       = aws_iam_role.s3_replication.arn
  description = "IAM role ARN used by S3 CRR service for replication"
}

output "dr_s3_kms_key_arn" {
  value       = aws_kms_key.dr_s3.arn
  description = "DR S3 KMS key ARN — encrypts all DR S3 bucket objects"
}

# ============================================
# SECTION 5 — DR EKS Warm Standby
# ============================================

output "dr_eks_cluster_name" {
  value       = var.enable_dr_eks ? aws_eks_cluster.dr[0].name : null
  description = "DR EKS cluster name in eu-west-1"
}

output "dr_eks_cluster_endpoint" {
  value       = var.enable_dr_eks ? aws_eks_cluster.dr[0].endpoint : null
  description = "DR EKS cluster API server endpoint"
}

output "dr_eks_cluster_arn" {
  value       = var.enable_dr_eks ? aws_eks_cluster.dr[0].arn : null
  description = "DR EKS cluster ARN"
}

output "dr_eks_cluster_ca_certificate" {
  value       = var.enable_dr_eks ? aws_eks_cluster.dr[0].certificate_authority[0].data : null
  description = "DR EKS cluster CA certificate — base64 encoded"
  sensitive   = true
}

output "dr_eks_oidc_issuer" {
  value       = var.enable_dr_eks ? aws_eks_cluster.dr[0].identity[0].oidc[0].issuer : null
  description = "DR EKS OIDC issuer URL — used for IRSA trust policies"
}

output "dr_eks_oidc_provider_arn" {
  value       = var.enable_dr_eks ? aws_iam_openid_connect_provider.dr_eks[0].arn : null
  description = "DR EKS OIDC provider ARN — Federated principal in IRSA trust policies"
}

output "dr_eks_node_role_arn" {
  value       = aws_iam_role.dr_eks_nodes.arn
  description = "DR EKS node IAM role ARN"
}

output "dr_nlb_dns_name" {
  value       = var.enable_dr_eks ? aws_lb.dr_nlb[0].dns_name : null
  description = "DR NLB DNS name — CloudFront DR distribution origin"
}

output "dr_nlb_arn" {
  value       = var.enable_dr_eks ? aws_lb.dr_nlb[0].arn : null
  description = "DR NLB ARN"
}

output "dr_nlb_arn_suffix" {
  value       = var.enable_dr_eks ? aws_lb.dr_nlb[0].arn_suffix : null
  description = "DR NLB ARN suffix — used in CloudWatch metric dimensions"
}

# ============================================
# SECTION 6 — DR DNS Failover
# ============================================

output "dr_cloudfront_distribution_id" {
  value       = aws_cloudfront_distribution.dr.id
  description = "DR CloudFront distribution ID"
}

output "dr_cloudfront_domain_name" {
  value       = aws_cloudfront_distribution.dr.domain_name
  description = "DR CloudFront auto-generated domain — dXXX.cloudfront.net"
}

output "dr_cloudfront_arn" {
  value       = aws_cloudfront_distribution.dr.arn
  description = "DR CloudFront distribution ARN"
}

output "dr_certificate_arn" {
  value       = aws_acm_certificate_validation.dr_cloudfront.certificate_arn
  description = "Validated ACM certificate ARN for DR CloudFront — in us-east-1"
}

output "route53_primary_health_check_id" {
  value       = aws_route53_health_check.primary.id
  description = "Route53 health check ID for primary (af-south-1) endpoint"
}

output "route53_dr_health_check_id" {
  value       = aws_route53_health_check.dr.id
  description = "Route53 health check ID for DR (eu-west-1) endpoint"
}

output "route53_hosted_zone_id" {
  value       = data.aws_route53_zone.main.zone_id
  description = "Route53 hosted zone ID for absa.co.za"
}

output "banking_domain" {
  value       = "banking.${var.domain_name}"
  description = "The customer-facing banking domain — banking.absa.co.za"
}

# ============================================
# SECTION 7 — DR Health Monitoring
# ============================================

output "dr_ops_sns_topic_arn" {
  value       = aws_sns_topic.dr_ops.arn
  description = "DR operations SNS topic ARN in eu-west-1 — subscribe ops team here"
}

output "dr_ops_us_east_1_sns_topic_arn" {
  value       = aws_sns_topic.dr_ops_us_east_1.arn
  description = "DR operations SNS topic ARN in us-east-1 — CloudFront alarms publish here"
}

output "dr_alerts_sns_topic_arn" {
  value       = aws_sns_topic.dr_alerts.arn
  description = "DR database alerts SNS topic ARN in eu-west-1 — RDS replication alarms"
}

output "route53_alerts_sns_topic_arn" {
  value       = aws_sns_topic.route53_alerts.arn
  description = "Route53 failover alerts SNS topic ARN in us-east-1 — DNS health check alarms"
}

output "dr_dashboard_url" {
  value       = "https://eu-west-1.console.aws.amazon.com/cloudwatch/home?region=eu-west-1#dashboards:name=ABSA-DR-Infrastructure-Health"
  description = "Direct URL to DR infrastructure health CloudWatch dashboard"
}

output "dr_readiness_alarm_arn" {
  value       = aws_cloudwatch_composite_alarm.dr_readiness.arn
  description = "DR overall readiness composite alarm ARN — OK = DR ready for failover"
}

# ============================================
# SECTION 8 — Failover Connection Information
# ============================================
# Consolidated connection map for DR activation runbook.
# During failover, application teams update their
# configuration with these values.
# Equivalent to Week 5's connection_info output
# but for the DR region.

output "dr_connection_info" {
  value = {
    rds_writer_endpoint = aws_rds_cluster.dr.endpoint
    rds_reader_endpoint = aws_rds_cluster.dr.reader_endpoint
    rds_port            = aws_rds_cluster.dr.port
    rds_database        = aws_rds_cluster.dr.database_name
    nlb_dns_name        = var.enable_dr_eks ? aws_lb.dr_nlb[0].dns_name : null
    eks_cluster_name    = var.enable_dr_eks ? aws_eks_cluster.dr[0].name : null
    eks_api_endpoint    = var.enable_dr_eks ? aws_eks_cluster.dr[0].endpoint : null
    cloudfront_domain   = aws_cloudfront_distribution.dr.domain_name
    banking_url         = "https://banking.${var.domain_name}"
    primary_region      = var.primary_region
    dr_region           = var.dr_region
  }
  description = "Complete DR connection information map for failover runbook"
}

# ============================================
# SECTION 9 — Week 8 Summary
# ============================================

output "week_8_summary" {
  value = {
    # Regions
    primary_region = var.primary_region
    dr_region      = var.dr_region

    # Network
    dr_vpc_cidr            = local.dr_vpc_cidr
    dr_subnets_created     = 9
    dr_security_groups     = 3
    dr_nat_gateways        = length(local.dr_availability_zones)
    dr_vpc_endpoints       = 7
    dr_availability_zones  = local.dr_availability_zones

    # KMS
    dr_kms_keys_created = 3

    # Database
    dr_rds_replica_created     = true
    dr_rds_cluster_id          = aws_rds_cluster.dr.cluster_identifier
    rpo_target_seconds         = var.rds_replication_lag_alert_threshold
    dr_rds_deletion_protection = true

    # S3 Replication
    s3_replication_configured  = true
    s3_buckets_replicated      = 2
    s3_replication_sla_minutes = 15

    # EKS
    dr_eks_enabled     = var.enable_dr_eks
    dr_eks_node_count  = var.dr_eks_node_count
    dr_eks_max_nodes   = 6
    dr_eks_version     = "1.32"
    dr_eks_addons      = 4

    # DNS Failover
    failover_ttl_seconds    = var.failover_ttl
    failover_threshold      = 3
    failover_check_interval = 30
    max_failover_time_seconds = (3 * 30) + var.failover_ttl
    human_intervention_required = false

    # Monitoring
    cloudwatch_alarms_created  = 9
    cloudwatch_dashboard       = "ABSA-DR-Infrastructure-Health"
    sns_topics_created         = 4
    composite_alarm_created    = true
  }
  description = "Complete summary of all Week 8 disaster recovery resources"
}