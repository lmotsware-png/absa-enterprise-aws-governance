# ============================================
# ECR Repositories — Container Image Registry
# ============================================
#
# ECR (Elastic Container Registry) is AWS's managed
# Docker registry. This file creates:
#
#   1. ECR repositories — one per application
#      (payment-api, fraud-detection)
#
#   2. Lifecycle policies — automatic image cleanup
#      retaining only the last N images per repo
#
#   3. Repository policies — resource-based access
#      control declaring which roles can push/pull
#
#   4. ECR cross-region replication — automatically
#      copies every pushed image from af-south-1
#      to eu-west-1 so the DR EKS cluster always
#      has access to current images during failover
#
#   5. ECR pull-through cache rules — for base images
#      (amazoncorretto, public.ecr.aws images) so
#      CodeBuild pulls base images from ECR rather
#      than Docker Hub (rate-limited) or public ECR
#
# Image tagging strategy:
#   Every image is tagged with TWO tags:
#     - Git commit SHA: absa/payment-api:abc1234
#       (immutable, exact traceability to source commit)
#     - Semantic version: absa/payment-api:v1.2.3
#       (human-readable, set from git tag if present)
#   The pipeline always deploys by commit SHA —
#   never by a mutable tag like "latest".
#   "latest" tag is explicitly excluded from lifecycle.
#
# Scanning strategy:
#   Enhanced scanning (AWS Inspector) runs on every push.
#   Findings are visible in ECR console + Security Hub.
#   Pipeline does NOT fail on scan findings —
#   findings generate CloudWatch alarm if CRITICAL.
# ============================================

# ============================================
# SECTION 1 — ECR Repositories
# ============================================
# One repository per application using for_each.
# var.applications map keys: payment_api, fraud_detection
# local.ecr_repo_names: absa/payment-api, absa/fraud-detection

resource "aws_ecr_repository" "apps" {
  for_each = var.applications

  name                 = local.ecr_repo_names[each.key]
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = var.ecr_scan_on_push
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = local.kms_s3_arn
  }

  tags = merge(local.common_tags, {
    Name        = "ABSA-ECR-${local.app_names[each.key]}"
    Application = each.value.display_name
  })
}

# ============================================
# SECTION 2 — ECR Lifecycle Policies
# ============================================
# Lifecycle policies automatically delete old images
# to prevent unbounded storage growth.
#
# Strategy:
#   Rule 1: Keep the last N tagged images
#           (N = var.ecr_image_retention_count = 30)
#   Rule 2: Delete ALL untagged images after 1 day
#
# Why two rules?
#   Docker builds produce intermediate layers and
#   failed builds that leave untagged images in ECR.
#   Without Rule 2, these accumulate indefinitely.
#   Rule 1 retains the last 30 deployable images —
#   enough for rollback to any recent deployment.

resource "aws_ecr_lifecycle_policy" "apps" {
  for_each = var.applications

  repository = aws_ecr_repository.apps[each.key].name

  policy = jsonencode({
    rules = [
      {
        # Rule 1: Retain only the last N tagged images
        # When the 31st image is pushed, the oldest is deleted
        rulePriority = 1
        description  = "Retain last ${var.ecr_image_retention_count} tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "sha-", "git-"]
          countType     = "imageCountMoreThan"
          countNumber   = var.ecr_image_retention_count
        }
        action = {
          type = "expire"
        }
      },
      {
        # Rule 2: Delete untagged images after 1 day
        # Untagged = intermediate build layers, failed builds
        rulePriority = 2
        description  = "Delete untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# ============================================
# SECTION 3 — ECR Repository Policies
# ============================================
# Resource-based policies on each ECR repository
# declaring which IAM principals can push and pull.
#
# Two separate permission sets:
#   PUSH: CodeBuild execution role + ECR push role
#         (produces images)
#   PULL: CodeBuild role + EKS node roles
#         (builds consume images during test stages,
#          EKS nodes pull images during pod scheduling)
#
# aws:SourceAccount condition prevents cross-account
# access even if an external principal knows the
# repository URI. Only this account's principals
# can use these permissions.

resource "aws_ecr_repository_policy" "apps" {
  for_each = var.applications

  repository = aws_ecr_repository.apps[each.key].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCodeBuildPush"
        Effect = "Allow"
        Principal = {
          AWS = [
            aws_iam_role.codebuild.arn,
            aws_iam_role.ecr_push.arn
          ]
        }
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart"
        ]
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AllowEKSNodePull"
        Effect = "Allow"
        Principal = {
          AWS = [
            # Primary EKS node role — pulls images for pod scheduling
            data.terraform_remote_state.production.outputs.eks_node_role_arn,
            # CodeBuild role — pulls images during integration tests
            aws_iam_role.codebuild.arn
          ]
        }
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetAuthorizationToken",
          "ecr:DescribeImages",
          "ecr:DescribeRepositories",
          "ecr:ListImages"
        ]
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AllowDREKSNodePull"
        Effect = "Allow"
        Principal = {
          AWS = [
            # DR EKS node role — pulls images for DR pod scheduling
            data.terraform_remote_state.disaster_recovery.outputs.dr_eks_node_role_arn
          ]
        }
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetAuthorizationToken",
          "ecr:DescribeImages"
        ]
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AllowScanningService"
        Effect = "Allow"
        Principal = {
          Service = "inspector.amazonaws.com"
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetAuthorizationToken",
          "ecr:DescribeImages",
          "ecr:ListImages"
        ]
      }
    ]
  })
}

# ============================================
# SECTION 4 — ECR Scanning Notification
# ============================================
# CloudWatch/EventBridge alarm fires when Inspector
# finds CRITICAL severity vulnerabilities in pushed images.
# The pipeline continues deploying (findings don't block)
# but the security team is immediately notified.
#
# EventBridge rule → SNS topic → security team email
# This implements the "scan but don't block" philosophy:
# banking deployments cannot be halted indefinitely by
# a newly discovered CVE — the security team receives
# the alert and decides whether to roll back or patch.

resource "aws_sns_topic" "ecr_scan_alerts" {
  name              = "absa-devops-ecr-scan-alerts"
  kms_master_key_id = local.kms_s3_arn

  tags = merge(local.common_tags, {
    Name = "ABSA-DevOps-ECR-Scan-Alerts"
  })
}

resource "aws_cloudwatch_event_rule" "ecr_scan_findings" {
  name        = "absa-devops-ecr-critical-findings"
  description = "Fires when ECR image scan finds CRITICAL severity vulnerabilities"

  event_pattern = jsonencode({
    source      = ["aws.inspector2"]
    "detail-type" = ["Inspector2 Finding"]
    detail = {
      severity = ["CRITICAL"]
      resources = {
        type = ["AWS_ECR_CONTAINER_IMAGE"]
      }
    }
  })

  tags = merge(local.common_tags, {
    Name = "ABSA-DevOps-ECR-Critical-Findings-Rule"
  })
}

resource "aws_cloudwatch_event_target" "ecr_scan_to_sns" {
  rule      = aws_cloudwatch_event_rule.ecr_scan_findings.name
  target_id = "ECRScanAlertToSNS"
  arn       = aws_sns_topic.ecr_scan_alerts.arn
}

resource "aws_sns_topic_policy" "ecr_scan_alerts" {
  arn = aws_sns_topic.ecr_scan_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowEventBridgePublish"
      Effect = "Allow"
      Principal = {
        Service = "events.amazonaws.com"
      }
      Action   = "sns:Publish"
      Resource = aws_sns_topic.ecr_scan_alerts.arn
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })
}

# ============================================
# SECTION 5 — ECR Cross-Region Replication
# ============================================
# Automatically copies every pushed image from
# af-south-1 (primary ECR) to eu-west-1 (DR ECR).
#
# How it works:
#   1. CodeBuild pushes payment-api:abc1234 to af-south-1 ECR
#   2. ECR replication rule detects the push
#   3. ECR automatically copies to eu-west-1 ECR
#   4. DR EKS nodes can pull from eu-west-1 ECR during failover
#
# Replication is configured at the REGISTRY level
# (one aws_ecr_replication_configuration per account)
# not at the repository level. It applies to all
# repositories matching the prefix filter.
#
# Replication lag: typically 1-5 minutes after push.
# During normal operation this is acceptable —
# DR deployment stage runs after primary deployment,
# giving replication time to complete before DR
# EKS nodes need to pull the image.

resource "aws_ecr_replication_configuration" "dr" {
  replication_configuration {
    rule {
      destination {
        region      = var.dr_region
        registry_id = data.aws_caller_identity.current.account_id
      }

      repository_filter {
        filter      = "absa/"
        filter_type = "PREFIX_MATCH"
      }
    }
  }
}

# ============================================
# SECTION 6 — ECR Pull-Through Cache
# ============================================
# Pull-through cache rules allow CodeBuild and EKS
# to pull base images (amazoncorretto, alpine, etc.)
# from an ECR-managed cache rather than directly
# from Docker Hub or public.ecr.aws.
#
# Benefits:
#   1. Docker Hub rate limiting: Docker Hub limits
#      unauthenticated pulls to 100/6hours per IP.
#      CodeBuild NAT Gateway has one IP — hits this
#      limit quickly in a busy build environment.
#   2. Network cost: pulling from ECR (same region)
#      costs less than pulling from public registries.
#   3. Availability: base images are cached in ECR
#      even if Docker Hub or public ECR is temporarily
#      unavailable.
#   4. Auditability: all base image pulls are logged
#      in CloudTrail via ECR API calls.
#
# First pull: ECR fetches from upstream and caches.
# Subsequent pulls: served from ECR cache.
# Cache expiry: 24 hours (ECR managed).

resource "aws_ecr_pull_through_cache_rule" "public_ecr" {
  ecr_repository_prefix = "ecr-public"
  upstream_registry_url = "public.ecr.aws"
}

resource "aws_ecr_pull_through_cache_rule" "docker_hub" {
  ecr_repository_prefix = "docker-hub"
  upstream_registry_url = "registry-1.docker.io"
  credential_arn        = aws_secretsmanager_secret.docker_hub_credentials.arn
}

# Docker Hub credentials — required for authenticated pulls.
# Unauthenticated Docker Hub pulls: 100/6hrs per IP (shared NAT).
# Authenticated Docker Hub pulls: 200/6hrs per account.
# Store credentials in Secrets Manager before first pipeline run.

resource "aws_secretsmanager_secret" "docker_hub_credentials" {
  name        = "absa/devops/docker-hub-credentials"
  description = "Docker Hub credentials for ECR pull-through cache"

  kms_key_id              = local.kms_s3_arn
  recovery_window_in_days = 30

  tags = merge(local.common_tags, {
    Name = "ABSA-DevOps-DockerHub-Credentials"
  })
}

# NOTE: The actual Docker Hub username/token is NOT set
# in Terraform — store it manually after terraform apply:
#
# aws secretsmanager put-secret-value \
#   --secret-id absa/devops/docker-hub-credentials \
#   --secret-string '{"username":"your-dockerhub-username","accessToken":"your-access-token"}'
#
# Use a Docker Hub access token (not your password).
# Tokens can be scoped to read-only and revoked independently.

# ============================================
# SECTION 7 — ECR Registry Scanning Configuration
# ============================================
# Configure enhanced scanning at the registry level.
# Enhanced scanning uses AWS Inspector and provides:
#   - Continuous scanning (not just on push)
#   - OS package CVE detection
#   - Programming language package CVE detection
#   - Integration with AWS Security Hub
#
# Enhanced vs Basic scanning:
#   Basic:    On push only, static CVE database snapshot
#   Enhanced: Continuous, live CVE feeds,
#             language package support, Security Hub

resource "aws_ecr_registry_scanning_configuration" "main" {
  scan_type = "ENHANCED"

  rule {
    scan_frequency = "SCAN_ON_PUSH"

    repository_filter {
      filter      = "absa/*"
      filter_type = "WILDCARD"
    }
  }

  rule {
    scan_frequency = "CONTINUOUS_SCAN"

    repository_filter {
      filter      = "absa/*"
      filter_type = "WILDCARD"
    }
  }
}

# ============================================
# SECTION 8 — Locals for ECR values consumed
#             by other files in this week
# ============================================
# These locals are consumed by:
#   iam_roles.tf    — ecr_repository_arns for policy Resource blocks
#   codebuild.tf    — ecr_repository_urls as env vars in build projects
#   codepipeline.tf — ecr_repository_urls for pipeline env context

locals {
  # Repository ARNs — used in IAM policy Resource blocks
  # to scope ECR push/pull permissions to only these repos
  ecr_repository_arns = {
    for key, repo in aws_ecr_repository.apps :
    key => repo.arn
  }

  # Repository URLs — injected into CodeBuild as
  # $ECR_REPOSITORY_URI environment variable.
  # Buildspec uses: $ECR_REPOSITORY_URI:$CODEBUILD_RESOLVED_SOURCE_VERSION
  # Produces: 123456789012.dkr.ecr.af-south-1.amazonaws.com/absa/payment-api:abc1234
  ecr_repository_urls = {
    for key, repo in aws_ecr_repository.apps :
    key => repo.repository_url
  }
}