# ============================================
# ABSA Enterprise AWS — Week 9: DevOps
# ============================================
#
# This week builds the CI/CD pipeline that automates
# application deployment across the entire ABSA platform.
#
# Pipeline flow for each application:
#   1. Developer pushes code to CodeCommit
#   2. CodePipeline detects the push (EventBridge trigger)
#   3. CodeBuild: compile, unit test, SAST scan
#   4. CodeBuild: Docker build + Trivy image scan
#   5. CodeBuild: push image to ECR (primary + DR region)
#   6. CodeDeploy: rolling update to primary EKS (af-south-1)
#   7. CodeDeploy: rolling update to DR EKS (eu-west-1)
#   8. CodeBuild: integration tests against primary
#   9. SNS notification: deployment success/failure
#
# Applications with pipelines:
#   - payment-api        (Week 5 EKS payment-api namespace)
#   - fraud-detection    (Week 5 EKS fraud-detection namespace)
#
# Remote state reads:
#   Week 2: VPC and subnet IDs (CodeBuild VPC config)
#   Week 3: KMS keys (artifact encryption), ECR policies
#   Week 5: EKS cluster names, OIDC providers (IRSA)
#   Week 8: DR EKS cluster name, DR region config
#
# All resources in af-south-1 (primary) unless noted.
# ECR push replication to eu-west-1 via ECR replication rules.
# ============================================

terraform {
  required_version = ">= 1.8.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.22.0"
    }
  }

  backend "s3" {
    bucket         = "absa-terraform-state-af-south-1"
    key            = "09-devops/terraform.tfstate"
    region         = "af-south-1"
    dynamodb_table = "absa-terraform-locks"
    encrypt        = true
  }
}

# ============================================
# PROVIDERS
# ============================================
# Two providers: primary (af-south-1) and DR (eu-west-1).
# The DR provider is needed for:
#   - ECR replication configuration
#   - DR EKS deployment stage in CodePipeline
#   - CodeBuild projects that deploy to DR EKS

provider "aws" {
  region = var.primary_region

  default_tags {
    tags = {
      Environment = "Production"
      Project     = "ABSA-Enterprise-AWS"
      ManagedBy   = "Terraform"
      Week        = "09-DevOps"
    }
  }
}

provider "aws" {
  alias  = "dr"
  region = var.dr_region

  default_tags {
    tags = {
      Environment = "Production"
      Project     = "ABSA-Enterprise-AWS"
      ManagedBy   = "Terraform"
      Week        = "09-DevOps"
    }
  }
}

# ============================================
# REMOTE STATE — Prior Weeks
# ============================================

# Week 2 — Networking
# Used by: CodeBuild VPC config (build projects run inside VPC
# to access internal resources like test databases)
data "terraform_remote_state" "networking" {
  backend = "s3"
  config = {
    bucket = "absa-terraform-state-af-south-1"
    key    = "02-networking/terraform.tfstate"
    region = "af-south-1"
  }
}

# Week 3 — Security
# Used by: KMS key for artifact bucket encryption,
# ECR repository policies referencing security principals
data "terraform_remote_state" "security" {
  backend = "s3"
  config = {
    bucket = "absa-terraform-state-af-south-1"
    key    = "03-security/terraform.tfstate"
    region = "af-south-1"
  }
}

# Week 5 — Production
# Used by: EKS cluster name (CodeDeploy target),
# EKS OIDC provider (CodeBuild IRSA role),
# ECR repository names (image push destination),
# VPC ID and subnet IDs for CodeBuild projects
data "terraform_remote_state" "production" {
  backend = "s3"
  config = {
    bucket = "absa-terraform-state-af-south-1"
    key    = "05-production/terraform.tfstate"
    region = "af-south-1"
  }
}

# Week 8 — Disaster Recovery
# Used by: DR EKS cluster name (secondary deploy stage),
# DR region (ECR replication destination),
# DR VPC config (CodeBuild DR deployment projects)
data "terraform_remote_state" "disaster_recovery" {
  backend = "s3"
  config = {
    bucket = "absa-terraform-state-af-south-1"
    key    = "08-disaster-recovery/terraform.tfstate"
    region = "af-south-1"
  }
}

# ============================================
# CURRENT IDENTITY
# ============================================

data "aws_caller_identity" "current" {}