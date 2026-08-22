# ============================================
# Outputs — Week 9 DevOps
# ============================================
#
# This is the final outputs file of the entire
# ABSA Enterprise AWS Landing Zone project.
#
# These outputs expose the CI/CD pipeline infrastructure
# to operational tooling, runbooks, dashboards, and
# any future automation built on top of this project.
#
# Output categories:
#   1. ECR Repositories
#   2. CodeCommit Repositories
#   3. CodePipeline Pipelines
#   4. CodeBuild Projects
#   5. S3 Artifact Bucket
#   6. IAM Roles
#   7. SSM Parameters
#   8. Notifications
#   9. Developer Quick Reference
#  10. Week 9 Summary
#  11. Complete Project Summary
# ============================================

# ============================================
# SECTION 1 — ECR Repositories
# ============================================

output "ecr_repository_urls" {
  value       = local.ecr_repository_urls
  description = "ECR repository URLs per application — use as Docker push targets"
}

output "ecr_repository_arns" {
  value       = local.ecr_repository_arns
  description = "ECR repository ARNs — used in IAM policies for push/pull permissions"
}

output "ecr_registry_url" {
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.primary_region}.amazonaws.com"
  description = "ECR registry base URL — authenticate with: aws ecr get-login-password | docker login --username AWS --password-stdin <this>"
}

output "dr_ecr_registry_url" {
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.dr_region}.amazonaws.com"
  description = "DR ECR registry base URL in eu-west-1 — images replicated here automatically"
}

# ============================================
# SECTION 2 — CodeCommit Repositories
# ============================================

output "codecommit_repo_urls" {
  value       = local.codecommit_clone_urls_http
  description = "CodeCommit HTTPS clone URLs per application — developers use these to clone"
}

output "codecommit_repo_arns" {
  value       = local.codecommit_repo_arns
  description = "CodeCommit repository ARNs"
}

# ============================================
# SECTION 3 — CodePipeline Pipelines
# ============================================

output "pipeline_arns" {
  value       = local.pipeline_arns
  description = "CodePipeline ARNs per application"
}

output "pipeline_names" {
  value = {
    for key, app in var.applications :
    key => local.pipeline_names[key]
  }
  description = "CodePipeline pipeline names per application"
}

output "pipeline_console_urls" {
  value = {
    for key, app in var.applications :
    key => "https://${var.primary_region}.console.aws.amazon.com/codesuite/codepipeline/pipelines/${local.pipeline_names[key]}/view"
  }
  description = "Direct console URLs to each pipeline — bookmark these for deployment monitoring"
}

# ============================================
# SECTION 4 — CodeBuild Projects
# ============================================

output "codebuild_project_names" {
  value = {
    for key, app in var.applications : key => {
      build            = local.codebuild_project_names[key].build
      push             = local.codebuild_project_names[key].push
      deploy           = local.codebuild_project_names[key].deploy
      dr_deploy        = local.codebuild_project_names[key].dr_deploy
      integration_test = local.codebuild_project_names[key].integration_test
    }
  }
  description = "CodeBuild project names per application and stage"
}

output "codebuild_log_groups" {
  value = {
    for key, app in var.applications : key => {
      build            = "/aws/codebuild/${local.codebuild_project_names[key].build}"
      push             = "/aws/codebuild/${local.codebuild_project_names[key].push}"
      deploy           = "/aws/codebuild/${local.codebuild_project_names[key].deploy}"
      integration_test = "/aws/codebuild/${local.codebuild_project_names[key].integration_test}"
    }
  }
  description = "CloudWatch log group paths for each CodeBuild project — use for build debugging"
}

# ============================================
# SECTION 5 — S3 Artifact Bucket
# ============================================

output "artifact_bucket_name" {
  value       = local.artifact_bucket_id
  description = "CodePipeline artifact S3 bucket name"
}

output "artifact_bucket_arn" {
  value       = local.artifact_bucket_arn
  description = "CodePipeline artifact S3 bucket ARN"
}

# ============================================
# SECTION 6 — IAM Roles
# ============================================

output "iam_role_arns" {
  value = {
    codepipeline = local.codepipeline_role_arn
    codebuild    = local.codebuild_role_arn
    ecr_push     = local.ecr_push_role_arn
    eks_deploy   = local.eks_deploy_role_arn
    codedeploy   = local.codedeploy_role_arn
  }
  description = "All DevOps pipeline IAM role ARNs — eks_deploy must be added to EKS aws-auth ConfigMap"
}

output "eks_deploy_role_arn" {
  value       = local.eks_deploy_role_arn
  description = <<-EOT
    EKS deployment IAM role ARN.

    CRITICAL: Add this to BOTH EKS clusters aws-auth ConfigMap:

    kubectl edit configmap aws-auth -n kube-system

    Add under mapRoles:
      - rolearn: <this_value>
        username: codebuild-deployer
        groups:
          - system:masters

    Without this, all pipeline deploy stages fail with Unauthorized.
  EOT
}

# ============================================
# SECTION 7 — SSM Parameters
# ============================================

output "ssm_parameter_paths" {
  value = {
    primary_cluster = "/absa/devops/primary-eks-cluster-name"
    dr_cluster      = "/absa/devops/dr-eks-cluster-name"
    primary_region  = "/absa/devops/primary-region"
    dr_region       = "/absa/devops/dr-region"
    ecr_registry    = "/absa/devops/ecr-registry"
    ecr_repos = {
      for key, app in var.applications :
      key => "/absa/devops/ecr-repo/${local.app_names[key]}"
    }
  }
  description = "SSM Parameter Store paths used by CodeBuild buildspecs"
}

# ============================================
# SECTION 8 — Notifications
# ============================================

output "pipeline_notifications_arn" {
  value       = local.pipeline_notifications_arn
  description = "SNS topic ARN for pipeline notifications — subscribe team email/PagerDuty here"
}

output "ecr_scan_alerts_arn" {
  value       = aws_sns_topic.ecr_scan_alerts.arn
  description = "SNS topic ARN for ECR CRITICAL vulnerability alerts — subscribe security team here"
}

output "devops_dashboard_url" {
  value       = "https://${var.primary_region}.console.aws.amazon.com/cloudwatch/home?region=${var.primary_region}#dashboards:name=ABSA-DevOps-Pipeline-Health"
  description = "Direct URL to DevOps pipeline health CloudWatch dashboard"
}

# ============================================
# SECTION 9 — Developer Quick Reference
# ============================================
# Consolidated reference for developers onboarding
# to the ABSA platform. Everything needed to start
# developing and deploying is in this one output.

output "developer_quick_reference" {
  value = {
    # Step 1: Clone the repository
    clone_payment_api = local.codecommit_clone_urls_http["payment_api"]
    clone_fraud_detection = local.codecommit_clone_urls_http["fraud_detection"]

    # Step 2: Authenticate to ECR before building locally
    ecr_login_command = "aws ecr get-login-password --region ${var.primary_region} | docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.primary_region}.amazonaws.com"

    # Step 3: Push to main branch to trigger pipeline
    trigger = "git push origin main"

    # Step 4: Watch the pipeline
    pipeline_payment_api     = "https://${var.primary_region}.console.aws.amazon.com/codesuite/codepipeline/pipelines/${local.pipeline_names["payment_api"]}/view"
    pipeline_fraud_detection = "https://${var.primary_region}.console.aws.amazon.com/codesuite/codepipeline/pipelines/${local.pipeline_names["fraud_detection"]}/view"

    # Step 5: Check deployment
    eks_cluster     = local.primary_eks_cluster_name
    eks_region      = var.primary_region
    kubeconfig_cmd  = "aws eks update-kubeconfig --name ${local.primary_eks_cluster_name} --region ${var.primary_region}"
    check_pods_cmd  = "kubectl get pods --all-namespaces"

    # Banking endpoint
    banking_url = "https://banking.absa.co.za"
  }
  description = "Complete developer onboarding quick reference — everything needed to start deploying"
}

# ============================================
# SECTION 10 — Week 9 Summary
# ============================================

output "week_9_summary" {
  value = {
    # Applications
    applications_managed    = length(var.applications)
    application_names       = [for k, v in var.applications : v.display_name]

    # ECR
    ecr_repositories        = length(var.applications)
    ecr_image_retention     = var.ecr_image_retention_count
    ecr_scanning_enabled    = var.ecr_scan_on_push
    ecr_replication_enabled = true
    ecr_replication_target  = var.dr_region

    # Source Control
    codecommit_repos        = length(var.applications)

    # CI/CD Pipelines
    pipelines_created       = length(var.applications)
    codebuild_projects      = length(var.applications) * 5
    manual_approval_enabled = var.require_manual_approval
    dr_deployment_enabled   = var.deploy_to_dr

    # Pipeline stages per application
    pipeline_stages = var.deploy_to_dr ? 7 : 6

    # Security
    sast_scanner            = "Semgrep (${var.semgrep_rules})"
    image_scanner           = "Trivy (CRITICAL,HIGH)"
    dependency_scanner      = "Safety (Python) / OWASP (Java)"
    scan_blocks_pipeline    = true

    # Infrastructure IaC Pipeline
    terraform_pipeline      = true
    terraform_validator     = "tfsec + checkov + infracost"

    # Notifications
    notification_email      = var.pipeline_notification_email
    sns_topics_created      = 2

    # Regions
    primary_region          = var.primary_region
    dr_region               = var.dr_region
  }
  description = "Summary of all Week 9 DevOps resources"
}

# ============================================
# SECTION 11 — COMPLETE PROJECT SUMMARY
# ============================================
# The final output of the entire ABSA Enterprise
# AWS Landing Zone project.
# Nine weeks. One complete banking platform.

output "absa_enterprise_aws_complete" {
  value = {

    project = "ABSA Enterprise AWS Landing Zone"
    author  = "LM Cloud Architect"
    version = "1.0.0"
    status  = "COMPLETE"

    # ---- Architecture ----
    primary_region      = var.primary_region
    dr_region           = var.dr_region
    banking_url         = "https://banking.absa.co.za"
    failover_url        = "https://banking.absa.co.za (auto-routed by Route53)"

    # ---- Weeks Deployed ----
    weeks_completed = {
      week_01 = "Governance — AWS Organizations, SCPs, CloudTrail"
      week_02 = "Networking — VPC, subnets, NAT Gateways, VPC endpoints"
      week_03 = "Security — KMS, WAF, GuardDuty, auto-remediation Lambda"
      week_04 = "Shared Services — centralized logging, AWS Config, CloudWatch"
      week_05 = "Production — EKS, Aurora, Redis, ALB, API Gateway, CloudFront"
      week_06 = "Data Platform — Kinesis, Firehose, Redshift, Athena, OpenSearch"
      week_07 = "Messaging — SQS, SNS, Amazon MQ (legacy integration)"
      week_08 = "Disaster Recovery — DR VPC, Aurora replica, S3 CRR, Route53 failover"
      week_09 = "DevOps — ECR, CodePipeline, CodeBuild, IaC validation pipeline"
    }

    # ---- Infrastructure Scale ----
    total_terraform_stacks   = 9
    total_aws_regions        = 2
    approximate_resources    = "400+"
    state_files              = 9

    # ---- Production Platform ----
    eks_cluster              = local.primary_eks_cluster_name
    aurora_database          = "Aurora PostgreSQL 16.4 (Multi-AZ)"
    redis_cache              = "ElastiCache Redis 7.1 (Multi-AZ)"
    api_gateway              = "REST API with CloudFront + WAF"
    cdn                      = "CloudFront PriceClass_All (includes Johannesburg)"

    # ---- Data Platform ----
    streaming_ingestion      = "Kinesis Data Streams (4 shards)"
    real_time_analytics      = "Kinesis Analytics (Flink 1.18)"
    data_lake                = "S3 + Firehose (Hive-style partitioning)"
    data_warehouse           = "Redshift ra3.xlplus (2 nodes)"
    search_analytics         = "OpenSearch 2.11 (3 nodes, dedicated masters)"
    sql_analytics            = "Athena (serverless, KMS encrypted)"

    # ---- Messaging ----
    event_queues             = "8 SQS queues (4 main + 4 DLQ)"
    event_topics             = "3 SNS topics"
    legacy_integration       = "Amazon MQ ActiveMQ 5.17.6"

    # ---- Security ----
    encryption_at_rest       = "KMS customer-managed keys (all data stores)"
    encryption_in_transit    = "TLS 1.2+ enforced everywhere"
    waf_rules                = 7
    network_isolation        = "Three-tier VPC (public/app/data)"
    secrets_management       = "AWS Secrets Manager + IRSA"
    vulnerability_scanning   = "GuardDuty + ECR Inspector + Semgrep + Trivy"
    compliance_monitoring    = "AWS Config + checkov + tfsec"
    auto_remediation         = "Lambda (public S3 bucket remediation)"

    # ---- Disaster Recovery ----
    dr_strategy              = "Warm standby"
    dr_rpo_seconds           = 300
    rto_dns_seconds          = 150
    rto_total_minutes        = 7
    dr_automation            = "Route53 health checks (fully automatic)"
    dr_database              = "Aurora cross-region replica (eu-west-1)"
    dr_replication           = "S3 CRR with 15-minute RTC SLA"

    # ---- CI/CD ----
    pipelines                = length(var.applications)
    pipeline_stages          = var.deploy_to_dr ? 7 : 6
    build_time_minutes       = "~11 (push to both EKS clusters)"
    security_gates           = "SAST + image scan + integration tests + manual approval"
    deployment_strategy      = "Kubernetes rolling update"
    dr_sync                  = var.deploy_to_dr

    # ---- Observability ----
    cloudwatch_dashboards    = 3
    cloudwatch_alarms        = "25+"
    log_retention_days       = 90
    audit_trail              = "CloudTrail (all regions, all services)"

    # ---- Cost Visibility ----
    cost_centers = {
      cloud_production = "Weeks 1-5 production infrastructure"
      cloud_analytics  = "Week 6 data platform"
      cloud_messaging  = "Week 7 messaging layer"
      cloud_dr         = "Week 8 disaster recovery"
      cloud_devops     = "Week 9 CI/CD pipeline"
    }
  }
  description = "Complete ABSA Enterprise AWS Landing Zone project summary — the full picture in one output"
}