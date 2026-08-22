# ============================================
# IAM Roles — DevOps Pipeline Service Roles
# ============================================
#
# This file creates five IAM roles, each for a
# distinct service principal with least-privilege
# permissions scoped to exactly what that service
# needs to perform its pipeline function.
#
# Role inventory:
#
#   1. ABSA-DevOps-CodePipeline-Role
#      Principal: codepipeline.amazonaws.com
#      Purpose:   Orchestrate pipeline stages,
#                 read from CodeCommit, write to
#                 artifact bucket, invoke CodeBuild
#
#   2. ABSA-DevOps-CodeBuild-Role
#      Principal: codebuild.amazonaws.com
#      Purpose:   Execute build projects, read/write
#                 artifact bucket, write CloudWatch logs,
#                 assume ECR push role and EKS deploy role
#
#   3. ABSA-DevOps-ECR-Push-Role
#      Principal: codebuild.amazonaws.com (assumed by CodeBuild)
#      Purpose:   Push Docker images to ECR repositories.
#                 Separated from CodeBuild role so ECR push
#                 is an explicit elevated action requiring
#                 role assumption — auditable in CloudTrail
#
#   4. ABSA-DevOps-EKS-Deploy-Role
#      Principal: codebuild.amazonaws.com (assumed by CodeBuild)
#      Purpose:   Call EKS API to update kubeconfig,
#                 then run kubectl commands against the
#                 primary and DR EKS clusters.
#                 This role must be in the EKS aws-auth
#                 ConfigMap with appropriate RBAC bindings.
#
#   5. ABSA-DevOps-CodeDeploy-Role
#      Principal: codedeploy.amazonaws.com
#      Purpose:   Reserved for CodeDeploy blue/green
#                 deployments if added in future.
#                 Currently EKS deployments run via
#                 CodeBuild kubectl — not CodeDeploy.
#
# IAM is a global service — no provider argument.
# All roles are in af-south-1 by default but are
# accessible from eu-west-1 CodeBuild projects too.
#
# Least privilege principle applied throughout:
#   - Resource ARNs scoped to specific buckets/repos
#   - No wildcard Resource blocks except where AWS
#     requires it (e.g., ecr:GetAuthorizationToken)
#   - Condition blocks on all cross-service trust
#   - Separate roles prevent lateral movement —
#     a compromised CodeBuild role cannot directly
#     push to ECR without the additional assumption
# ============================================

# ============================================
# ROLE 1 — CodePipeline Execution Role
# ============================================

resource "aws_iam_role" "codepipeline" {
  name        = local.iam_role_names.codepipeline
  description = "Service role for CodePipeline to orchestrate ABSA DevOps pipelines"
  path        = "/devops/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowCodePipelineAssumption"
      Effect = "Allow"
      Principal = {
        Service = "codepipeline.amazonaws.com"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })

  tags = merge(local.common_tags, {
    Name    = local.iam_role_names.codepipeline
    Service = "CodePipeline"
  })
}

resource "aws_iam_role_policy" "codepipeline" {
  name = "ABSA-DevOps-CodePipeline-Policy"
  role = aws_iam_role.codepipeline.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [

      # ---- S3 Artifact Bucket ----
      # CodePipeline reads source artifacts and writes
      # stage outputs between every pipeline stage.
      {
        Sid    = "ArtifactBucketAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetBucketVersioning",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          local.artifact_bucket_arn,
          "${local.artifact_bucket_arn}/*"
        ]
      },

      # ---- KMS — Artifact Encryption ----
      # CodePipeline must encrypt/decrypt artifacts
      # as it passes them between stages.
      {
        Sid    = "KMSArtifactAccess"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = local.kms_s3_arn
      },

      # ---- CodeCommit — Source Stage ----
      # Read source code from CodeCommit repositories
      # when a push triggers the pipeline source stage.
      {
        Sid    = "CodeCommitSourceAccess"
        Effect = "Allow"
        Action = [
          "codecommit:GetBranch",
          "codecommit:GetCommit",
          "codecommit:GetRepository",
          "codecommit:GetUploadArchiveStatus",
          "codecommit:UploadArchive",
          "codecommit:CancelUploadArchive"
        ]
        Resource = [
          for arn in local.codecommit_repo_arns : arn
        ]
      },

      # ---- CodeBuild — Build/Test/Deploy Stages ----
      # Start and monitor CodeBuild projects for each
      # pipeline stage (build, push, deploy, test).
      {
        Sid    = "CodeBuildInvocation"
        Effect = "Allow"
        Action = [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild",
          "codebuild:StopBuild"
        ]
        # Scope to only ABSA DevOps CodeBuild projects
        Resource = [
          "arn:aws:codebuild:${var.primary_region}:${data.aws_caller_identity.current.account_id}:project/${local.name_prefix}-*"
        ]
      },

      # ---- SNS — Pipeline Notifications ----
      # Publish pipeline execution events to the
      # notifications topic for team alerting.
      {
        Sid    = "SNSNotificationPublish"
        Effect = "Allow"
        Action = "sns:Publish"
        Resource = local.pipeline_notifications_arn
      },

      # ---- CloudWatch Logs — Pipeline Execution Logs ----
      {
        Sid    = "CloudWatchLogsAccess"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${var.primary_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codepipeline/*"
      },

      # ---- IAM PassRole ----
      # CodePipeline must pass its own role to CodeBuild
      # when starting build projects. Without this,
      # CodePipeline cannot authorize CodeBuild to
      # use specific roles for artifact access.
      {
        Sid    = "PassRoleToCodeBuild"
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = aws_iam_role.codebuild.arn
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "codebuild.amazonaws.com"
          }
        }
      }
    ]
  })
}

# ============================================
# ROLE 2 — CodeBuild Execution Role
# ============================================

resource "aws_iam_role" "codebuild" {
  name        = local.iam_role_names.codebuild
  description = "Service role for CodeBuild to execute ABSA pipeline build projects"
  path        = "/devops/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowCodeBuildAssumption"
      Effect = "Allow"
      Principal = {
        Service = "codebuild.amazonaws.com"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })

  tags = merge(local.common_tags, {
    Name    = local.iam_role_names.codebuild
    Service = "CodeBuild"
  })
}

resource "aws_iam_role_policy" "codebuild" {
  name = "ABSA-DevOps-CodeBuild-Policy"
  role = aws_iam_role.codebuild.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [

      # ---- S3 Artifact Bucket ----
      # Read input artifacts from prior stages,
      # write output artifacts for subsequent stages.
      {
        Sid    = "ArtifactBucketAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          local.artifact_bucket_arn,
          "${local.artifact_bucket_arn}/*"
        ]
      },

      # ---- KMS — Decrypt/Encrypt Artifacts ----
      {
        Sid    = "KMSAccess"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = local.kms_s3_arn
      },

      # ---- CloudWatch Logs ----
      # Every CodeBuild project writes its build logs
      # to CloudWatch Logs. Without this permission,
      # build output is invisible and debugging
      # pipeline failures becomes impossible.
      {
        Sid    = "CloudWatchLogsWrite"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:*:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/*"
      },

      # ---- ECR Authorization ----
      # GetAuthorizationToken is required for Docker to
      # authenticate with ECR before pull or push.
      # This action cannot be scoped to a specific
      # repository ARN — it is always Resource = "*".
      # The actual push/pull actions are scoped per-repo
      # in the ECR repository policy (ecr_repositories.tf).
      {
        Sid      = "ECRAuthorizationToken"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },

      # ---- ECR Image Pull ----
      # CodeBuild pulls the base image (amazoncorretto)
      # and the application image (for integration tests).
      # Scoped to ABSA's ECR repositories.
      {
        Sid    = "ECRImagePull"
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability",
          "ecr:DescribeImages"
        ]
        Resource = [
          for arn in local.ecr_repository_arns : arn
        ]
      },

      # ---- Secrets Manager ----
      # CodeBuild reads:
      #   absa/devops/docker-hub-credentials (pull-through cache)
      #   absa/devops/sonar-token (code quality scanning)
      #   absa/production/* (integration test DB credentials)
      {
        Sid    = "SecretsManagerRead"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          "arn:aws:secretsmanager:${var.primary_region}:${data.aws_caller_identity.current.account_id}:secret:absa/devops/*",
          "arn:aws:secretsmanager:${var.primary_region}:${data.aws_caller_identity.current.account_id}:secret:absa/production/*"
        ]
      },

      # ---- SSM Parameter Store ----
      # Read build configuration parameters:
      #   /absa/devops/eks-cluster-name
      #   /absa/devops/ecr-registry-url
      # Parameters used for non-secret configuration
      # values injected into buildspec environment.
      {
        Sid    = "SSMParameterRead"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = "arn:aws:ssm:${var.primary_region}:${data.aws_caller_identity.current.account_id}:parameter/absa/devops/*"
      },

      # ---- CodeCommit — Clone Source ----
      # CodeBuild clones the source repository during
      # the source checkout phase of each build.
      {
        Sid    = "CodeCommitClone"
        Effect = "Allow"
        Action = [
          "codecommit:GitPull",
          "codecommit:GetRepository",
          "codecommit:GetBranch",
          "codecommit:GetCommit"
        ]
        Resource = [
          for arn in local.codecommit_repo_arns : arn
        ]
      },

      # ---- Assume ECR Push Role ----
      # CodeBuild assumes the dedicated ECR push role
      # during the push stage. Separation creates an
      # explicit elevated action in the audit trail.
      {
        Sid    = "AssumeECRPushRole"
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Resource = aws_iam_role.ecr_push.arn
      },

      # ---- Assume EKS Deploy Role ----
      # CodeBuild assumes the dedicated EKS deploy role
      # during the primary and DR deploy stages.
      {
        Sid    = "AssumeEKSDeployRole"
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Resource = aws_iam_role.eks_deploy.arn
      },

      # ---- VPC — Required for CodeBuild VPC Config ----
      # When CodeBuild runs inside the VPC (for integration
      # tests that need Aurora/Redis access), it needs
      # permission to describe and use VPC resources.
      {
        Sid    = "VPCNetworkInterface"
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeDhcpOptions",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeVpcs",
          "ec2:CreateNetworkInterfacePermission"
        ]
        Resource = "*"
      },

      # ---- CodeBuild Report Groups ----
      # CodeBuild publishes unit test results as reports
      # viewable in the CodeBuild console. These permissions
      # enable the report publishing from the buildspec.
      {
        Sid    = "CodeBuildReportGroups"
        Effect = "Allow"
        Action = [
          "codebuild:CreateReportGroup",
          "codebuild:CreateReport",
          "codebuild:UpdateReport",
          "codebuild:BatchPutTestCases",
          "codebuild:BatchPutCodeCoverages"
        ]
        Resource = "arn:aws:codebuild:${var.primary_region}:${data.aws_caller_identity.current.account_id}:report-group/${local.name_prefix}-*"
      },

      # ---- CloudWatch Metrics ----
      # Publish custom build metrics to CloudWatch:
      # build duration, test pass rate, coverage percentage.
      {
        Sid      = "CloudWatchMetrics"
        Effect   = "Allow"
        Action   = "cloudwatch:PutMetricData"
        Resource = "*"
      }
    ]
  })
}

# ============================================
# ROLE 3 — ECR Push Role
# ============================================
# Assumed by CodeBuild during the push stage.
# Separated from the CodeBuild base role so that
# ECR image push is a distinct, auditable action.
# CloudTrail shows: CodeBuild assumed ECR push role,
# then pushed image — two separate, traceable events.

resource "aws_iam_role" "ecr_push" {
  name        = local.iam_role_names.ecr_push
  description = "Role assumed by CodeBuild to push Docker images to ECR"
  path        = "/devops/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowCodeBuildAssumption"
      Effect = "Allow"
      Principal = {
        AWS = aws_iam_role.codebuild.arn
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "sts:ExternalId" = "absa-ecr-push"
        }
      }
    }]
  })

  tags = merge(local.common_tags, {
    Name    = local.iam_role_names.ecr_push
    Service = "ECR"
  })
}

resource "aws_iam_role_policy" "ecr_push" {
  name = "ABSA-DevOps-ECR-Push-Policy"
  role = aws_iam_role.ecr_push.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [

      # ---- ECR Authorization ----
      # Must be Resource = "*" — AWS requirement.
      # GetAuthorizationToken generates a 12-hour token
      # that Docker uses to authenticate all ECR operations.
      {
        Sid      = "ECRAuthorizationToken"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },

      # ---- ECR Image Push ----
      # Scoped to only ABSA's ECR repository ARNs.
      # Cannot push to any other ECR repository in the account.
      {
        Sid    = "ECRImagePush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart"
        ]
        Resource = [
          for arn in local.ecr_repository_arns : arn
        ]
      },

      # ---- ECR Image Tag ----
      # Adds semantic version tag to the image after
      # the commit SHA tag is pushed.
      # Example: abc1234 gets tagged as v1.2.3 if a
      # git tag exists for this commit.
      {
        Sid    = "ECRImageTag"
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:DescribeImages",
          "ecr:ListImages"
        ]
        Resource = [
          for arn in local.ecr_repository_arns : arn
        ]
      },

      # ---- KMS — Encrypt Image Layers ----
      # ECR encryption requires KMS GenerateDataKey
      # when pushing layers to an encrypted repository.
      {
        Sid    = "KMSEncrypt"
        Effect = "Allow"
        Action = [
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = local.kms_s3_arn
      },

      # ---- ECR Scan Findings ----
      # After pushing, the push stage checks scan findings
      # for CRITICAL vulnerabilities and logs them.
      # Informational — does not block deployment.
      {
        Sid    = "ECRScanFindings"
        Effect = "Allow"
        Action = [
          "ecr:DescribeImageScanFindings",
          "ecr:StartImageScan"
        ]
        Resource = [
          for arn in local.ecr_repository_arns : arn
        ]
      }
    ]
  })
}

# ============================================
# ROLE 4 — EKS Deploy Role
# ============================================
# Assumed by CodeBuild during the deploy stages
# (both primary af-south-1 and DR eu-west-1).
#
# CRITICAL POST-DEPLOYMENT STEP:
# This role must be added to the EKS aws-auth
# ConfigMap in BOTH clusters before the deploy
# stage will work. Without this, kubectl commands
# fail with "You must be logged in to the server
# (Unauthorized)".
#
# Add to primary cluster:
#   kubectl edit configmap aws-auth -n kube-system
#   Add under mapRoles:
#     - rolearn: <eks_deploy_role_arn>
#       username: codebuild-deployer
#       groups:
#         - system:masters   # or a custom RBAC role
#
# In production, use a custom RBAC role scoped to
# only the namespaces this pipeline deploys to:
#   - payment-api namespace: deployment updates only
#   - fraud-detection namespace: deployment updates only
# system:masters is used here for simplicity —
# tighten to a custom ClusterRole in production.

resource "aws_iam_role" "eks_deploy" {
  name        = local.iam_role_names.eks_deploy
  description = "Role assumed by CodeBuild to deploy to EKS clusters"
  path        = "/devops/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowCodeBuildAssumption"
      Effect = "Allow"
      Principal = {
        AWS = aws_iam_role.codebuild.arn
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "sts:ExternalId" = "absa-eks-deploy"
        }
      }
    }]
  })

  tags = merge(local.common_tags, {
    Name    = local.iam_role_names.eks_deploy
    Service = "EKS"
  })
}

resource "aws_iam_role_policy" "eks_deploy" {
  name = "ABSA-DevOps-EKS-Deploy-Policy"
  role = aws_iam_role.eks_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [

      # ---- EKS Cluster Access ----
      # DescribeCluster: required to generate kubeconfig.
      # The deploy script runs:
      #   aws eks update-kubeconfig \
      #     --name <cluster-name> \
      #     --region <region> \
      #     --role-arn <this-role-arn>
      # ListClusters: enumerate available clusters
      # for validation before deployment.
      {
        Sid    = "EKSClusterAccess"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:AccessKubernetesApi"
        ]
        Resource = [
          # Primary EKS cluster
          "arn:aws:eks:${var.primary_region}:${data.aws_caller_identity.current.account_id}:cluster/${local.primary_eks_cluster_name}",
          # DR EKS cluster
          "arn:aws:eks:${var.dr_region}:${data.aws_caller_identity.current.account_id}:cluster/${local.dr_eks_cluster_name}"
        ]
      },

      # ---- ECR Pull ----
      # During deployment verification, the deploy stage
      # checks the image exists in ECR before applying
      # the Kubernetes manifest update.
      {
        Sid      = "ECRAuthorizationToken"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid    = "ECRImageVerify"
        Effect = "Allow"
        Action = [
          "ecr:DescribeImages",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]
        Resource = [
          for arn in local.ecr_repository_arns : arn
        ]
      },

      # ---- CloudWatch — Deployment Metrics ----
      # Publish deployment event metrics:
      # deployment timestamp, duration, success/failure.
      {
        Sid      = "CloudWatchMetrics"
        Effect   = "Allow"
        Action   = "cloudwatch:PutMetricData"
        Resource = "*"
      },

      # ---- Secrets Manager — Kubeconfig ----
      # Read EKS credentials if stored in Secrets Manager
      # rather than generated fresh via update-kubeconfig.
      {
        Sid    = "SecretsManagerEKS"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          "arn:aws:secretsmanager:${var.primary_region}:${data.aws_caller_identity.current.account_id}:secret:absa/devops/eks-*",
          "arn:aws:secretsmanager:${var.dr_region}:${data.aws_caller_identity.current.account_id}:secret:absa/devops/eks-*"
        ]
      }
    ]
  })
}

# ============================================
# ROLE 5 — CodeDeploy Role
# ============================================
# Reserved for future CodeDeploy blue/green
# deployment strategy if adopted.
# Currently EKS rolling updates run via CodeBuild
# kubectl — CodeDeploy is not the active mechanism.
# Creating the role now ensures it is available
# without requiring a new Terraform apply if the
# deployment strategy changes.

resource "aws_iam_role" "codedeploy" {
  name        = local.iam_role_names.codedeploy
  description = "Service role for CodeDeploy (reserved for blue/green EKS deployments)"
  path        = "/devops/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowCodeDeployAssumption"
      Effect = "Allow"
      Principal = {
        Service = "codedeploy.amazonaws.com"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })

  tags = merge(local.common_tags, {
    Name    = local.iam_role_names.codedeploy
    Service = "CodeDeploy"
  })
}

# AWS managed policy for CodeDeploy ECS deployments
# (closest match for container workload deployments)
resource "aws_iam_role_policy_attachment" "codedeploy" {
  role       = aws_iam_role.codedeploy.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
}

# ============================================
# SSM Parameters — Pipeline Configuration
# ============================================
# Store pipeline configuration values in SSM
# Parameter Store. These are read by CodeBuild
# buildspec files via the SSM parameter read
# permission granted to the CodeBuild role above.
#
# Using SSM rather than environment variables in
# CodeBuild project config means:
#   1. Values can be updated without re-applying Terraform
#   2. Values are visible in SSM console for auditing
#   3. Buildspec files can reference by parameter path
#      rather than hardcoded values

resource "aws_ssm_parameter" "primary_cluster_name" {
  name  = "/absa/devops/primary-eks-cluster-name"
  type  = "String"
  value = local.primary_eks_cluster_name

  description = "Primary EKS cluster name for CodeBuild deploy stage"

  tags = merge(local.common_tags, {
    Name = "ABSA-DevOps-Primary-EKS-Cluster-Name"
  })
}

resource "aws_ssm_parameter" "dr_cluster_name" {
  name  = "/absa/devops/dr-eks-cluster-name"
  type  = "String"
  value = local.dr_eks_cluster_name != null ? local.dr_eks_cluster_name : "not-configured"

  description = "DR EKS cluster name for CodeBuild DR deploy stage"

  tags = merge(local.common_tags, {
    Name = "ABSA-DevOps-DR-EKS-Cluster-Name"
  })
}

resource "aws_ssm_parameter" "primary_region" {
  name  = "/absa/devops/primary-region"
  type  = "String"
  value = var.primary_region

  description = "Primary AWS region for pipeline operations"

  tags = merge(local.common_tags, {
    Name = "ABSA-DevOps-Primary-Region"
  })
}

resource "aws_ssm_parameter" "dr_region" {
  name  = "/absa/devops/dr-region"
  type  = "String"
  value = var.dr_region

  description = "DR AWS region for pipeline DR deploy stage"

  tags = merge(local.common_tags, {
    Name = "ABSA-DevOps-DR-Region"
  })
}

# ECR registry URL — used in buildspec to construct
# full image URIs without hardcoding account ID
resource "aws_ssm_parameter" "ecr_registry" {
  name  = "/absa/devops/ecr-registry"
  type  = "String"
  value = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.primary_region}.amazonaws.com"

  description = "ECR registry URL for Docker image push/pull operations"

  tags = merge(local.common_tags, {
    Name = "ABSA-DevOps-ECR-Registry"
  })
}

# Per-application ECR repository URIs
resource "aws_ssm_parameter" "ecr_repo_uri" {
  for_each = var.applications

  name  = "/absa/devops/ecr-repo/${local.app_names[each.key]}"
  type  = "String"
  value = local.ecr_repository_urls[each.key]

  description = "ECR repository URI for ${each.value.display_name}"

  tags = merge(local.common_tags, {
    Name        = "ABSA-DevOps-ECR-Repo-URI-${local.app_names[each.key]}"
    Application = each.value.display_name
  })
}

# ============================================
# CloudWatch Log Groups for CodeBuild
# ============================================
# Pre-create log groups with retention policies.
# Without pre-creation, CodeBuild creates them
# with infinite retention — logs accumulate forever.
# 90-day retention matches artifact retention and
# covers compliance investigation windows.

resource "aws_cloudwatch_log_group" "codebuild" {
  for_each = {
    for combo in flatten([
      for app_key, app in var.applications : [
        for stage in ["build", "push", "deploy", "dr-deploy", "integration-test"] : {
          key      = "${app_key}-${stage}"
          app_key  = app_key
          stage    = stage
          app_name = local.app_names[app_key]
        }
      ]
    ]) : combo.key => combo
  }

  name              = "/aws/codebuild/${local.name_prefix}-${each.value.stage}-${each.value.app_name}"
  retention_in_days = 90

  tags = merge(local.common_tags, {
    Name        = "ABSA-DevOps-CodeBuild-Logs-${each.value.stage}-${each.value.app_name}"
    Application = each.value.app_key
    Stage       = each.value.stage
  })
}

# ============================================
# IAM Role ARN Outputs for Other Files
# ============================================

locals {
  # Role ARNs consumed by codebuild.tf, codepipeline.tf
  codepipeline_role_arn = aws_iam_role.codepipeline.arn
  codebuild_role_arn    = aws_iam_role.codebuild.arn
  ecr_push_role_arn     = aws_iam_role.ecr_push.arn
  eks_deploy_role_arn   = aws_iam_role.eks_deploy.arn
  codedeploy_role_arn   = aws_iam_role.codedeploy.arn
}