# ============================================
# ABSA Enterprise AWS — Week 9: DevOps
# locals.tf
# ============================================

locals {

  # ==========================================
  # COMMON TAGS
  # ==========================================
  # CostCenter = "Cloud-DevOps" — fourth new cost center
  # across the project after Cloud-Analytics (Week 6),
  # Cloud-Messaging (Week 7), Cloud-DR (Week 8).
  # DataClass = "Internal" — pipeline metadata, build logs,
  # artifact checksums. Not customer financial data.
  # Application source code is classified separately by
  # the source control system, not by these infrastructure tags.

  common_tags = {
    Project    = "ABSA-Enterprise-AWS"
    CostCenter = "Cloud-DevOps"
    DataClass  = "Internal"
    ManagedBy  = "Terraform"
  }

  # ==========================================
  # REMOTE STATE EXTRACTIONS — WEEK 2
  # ==========================================

  # VPC ID — CodeBuild projects that run integration tests
  # execute inside this VPC to reach the primary Aurora
  # database and Redis cache via their private endpoints.
  vpc_id = data.terraform_remote_state.networking.outputs.vpc_ids.production

  # App tier subnets — CodeBuild containers run here.
  # Same tier as EKS pods — can reach data tier services
  # via the Week 3 security group wristband system.
  app_subnet_ids = data.terraform_remote_state.networking.outputs.subnet_ids.production_app

  # App security group — CodeBuild containers carry this
  # identity. The baseline_data security group allows
  # inbound from baseline_app on ports 5432 (Aurora)
  # and 6379 (Redis) — enabling integration test DB access.
  app_security_group_id = data.terraform_remote_state.security.outputs.security_group_ids.baseline_app

  # ==========================================
  # REMOTE STATE EXTRACTIONS — WEEK 3
  # ==========================================

  # S3 KMS key — encrypts the CodePipeline artifact bucket.
  # Every artifact that passes between pipeline stages
  # (compiled JARs, Docker digests, test reports) is
  # encrypted at rest using this key.
  kms_s3_arn = data.terraform_remote_state.security.outputs.kms_key_arns.s3

  # ==========================================
  # REMOTE STATE EXTRACTIONS — WEEK 5
  # ==========================================

  # Primary EKS cluster name — the deployment target for
  # the primary deploy stage in each pipeline.
  # CodeBuild runs: aws eks update-kubeconfig --name <this>
  # before executing kubectl commands.
  primary_eks_cluster_name = data.terraform_remote_state.production.outputs.eks_cluster_name

  # Primary EKS cluster endpoint — used in CodeBuild
  # kubeconfig generation for kubectl to connect to.
  primary_eks_endpoint = data.terraform_remote_state.production.outputs.eks_cluster_endpoint

  # Primary OIDC provider ARN — referenced in IRSA trust
  # policies for the CodeBuild deployment role.
  # The CodeBuild project running kubectl needs to assume
  # an IAM role that is bound to a Kubernetes service account
  # in the cluster — the OIDC provider is the trust anchor.
  primary_oidc_provider_arn = data.terraform_remote_state.production.outputs.eks_oidc_provider_arn

  # Primary Aurora reader endpoint — integration test
  # CodeBuild projects connect here for DB schema tests.
  # Read-only endpoint prevents integration tests from
  # accidentally modifying production data.
  primary_rds_reader_endpoint = data.terraform_remote_state.production.outputs.rds_cluster_reader_endpoint

  # ==========================================
  # REMOTE STATE EXTRACTIONS — WEEK 8
  # ==========================================

  # DR EKS cluster name — the deployment target for the
  # secondary deploy stage (when var.deploy_to_dr = true).
  # Keeps DR cluster synchronized with primary at all times.
  dr_eks_cluster_name = data.terraform_remote_state.disaster_recovery.outputs.dr_eks_cluster_name

  # DR EKS cluster endpoint
  dr_eks_endpoint = data.terraform_remote_state.disaster_recovery.outputs.dr_eks_cluster_endpoint

  # ==========================================
  # RESOURCE NAMING
  # ==========================================
  # Consistent naming prefix applied to all Week 9 resources.
  # Format: absa-devops-<resource-type>-<application>
  # Examples:
  #   absa-devops-pipeline-payment-api
  #   absa-devops-ecr-fraud-detection
  #   absa-devops-codebuild-payment-api-build

  name_prefix = "absa-devops"

  # S3 artifact bucket name — globally unique via account ID.
  # One bucket for all pipelines — different prefixes per
  # pipeline organize artifacts within the bucket:
  #   payment-api/build/abc123/
  #   fraud-detection/build/def456/
  artifact_bucket_name = "${local.name_prefix}-artifacts-${data.aws_caller_identity.current.account_id}"

  # ==========================================
  # APPLICATION DERIVED VALUES
  # ==========================================
  # Compute derived naming from the applications variable.
  # Each application key (payment_api, fraud_detection)
  # generates consistent resource names without
  # repetition in resource files.
  # payment_api → payment-api (hyphens for AWS resource names)

  app_names = {
    for key, app in var.applications :
    key => replace(key, "_", "-")
  }

  # ECR repository names — one per application.
  # Format: absa/<app-name>
  # Full URI: <account>.dkr.ecr.af-south-1.amazonaws.com/absa/payment-api
  # The absa/ prefix namespaces ABSA repositories within
  # the account, separating them from any third-party
  # or vendor images stored in the same account's ECR.
  ecr_repo_names = {
    for key, app in var.applications :
    key => "absa/${local.app_names[key]}"
  }

  # CodeCommit repository names
  codecommit_repo_names = {
    for key, app in var.applications :
    key => "${local.name_prefix}-${local.app_names[key]}"
  }

  # CodePipeline pipeline names
  pipeline_names = {
    for key, app in var.applications :
    key => "${local.name_prefix}-pipeline-${local.app_names[key]}"
  }

  # CodeBuild project names — one per stage per application.
  # Each application has three CodeBuild projects:
  #   build   — compile, unit test, SAST, Docker build
  #   push    — Docker push to ECR (primary + DR ECR)
  #   deploy  — kubectl rolling update on EKS
  codebuild_project_names = {
    for key, app in var.applications : key => {
      build  = "${local.name_prefix}-build-${local.app_names[key]}"
      push   = "${local.name_prefix}-push-${local.app_names[key]}"
      deploy = "${local.name_prefix}-deploy-${local.app_names[key]}"
      dr_deploy = "${local.name_prefix}-dr-deploy-${local.app_names[key]}"
      integration_test = "${local.name_prefix}-integration-test-${local.app_names[key]}"
    }
  }

  # ==========================================
  # ECR REPOSITORY URIS
  # ==========================================
  # Constructed ECR URIs for each application.
  # Used in buildspec files to tag and push images.
  # Format: <account>.dkr.ecr.<region>.amazonaws.com/<repo>

  ecr_repository_uris = {
    for key, app in var.applications :
    key => "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.primary_region}.amazonaws.com/${local.ecr_repo_names[key]}"
  }

  # DR ECR repository URIs — images are replicated here
  # via ECR cross-region replication (ecr_repositories.tf).
  # The DR CodeBuild deploy project pulls from this URI.
  dr_ecr_repository_uris = {
    for key, app in var.applications :
    key => "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.dr_region}.amazonaws.com/${local.ecr_repo_names[key]}"
  }

  # ==========================================
  # IAM ROLE NAMES
  # ==========================================
  # Centralized role naming — referenced by both
  # iam_roles.tf (where roles are created) and
  # codebuild.tf/codepipeline.tf (where roles are used).

  iam_role_names = {
    codepipeline  = "ABSA-DevOps-CodePipeline-Role"
    codebuild     = "ABSA-DevOps-CodeBuild-Role"
    codedeploy    = "ABSA-DevOps-CodeDeploy-Role"
    ecr_push      = "ABSA-DevOps-ECR-Push-Role"
    eks_deploy    = "ABSA-DevOps-EKS-Deploy-Role"
  }

  # ==========================================
  # PIPELINE STAGE CONFIGURATION
  # ==========================================
  # Complete pipeline stage definition for each application.
  # Consumed by codepipeline.tf to build the stage sequence.
  # Centralizing here means codepipeline.tf reads a map
  # rather than duplicating stage logic per application.

  pipeline_stages = {
    for key, app in var.applications : key => [
      {
        name   = "Source"
        action = "CodeCommit"
        config = {
          repository_name = local.codecommit_repo_names[key]
          branch_name     = app.branch
        }
      },
      {
        name   = "Build"
        action = "CodeBuild"
        config = {
          project_name = local.codebuild_project_names[key].build
        }
      },
      {
        name   = "Push"
        action = "CodeBuild"
        config = {
          project_name = local.codebuild_project_names[key].push
        }
      },
      {
        name   = "Deploy-Primary"
        action = "CodeBuild"
        config = {
          project_name = local.codebuild_project_names[key].deploy
        }
      },
      {
        name   = "Integration-Test"
        action = "CodeBuild"
        config = {
          project_name = local.codebuild_project_names[key].integration_test
        }
      },
    ]
  }

  # ==========================================
  # NOTIFICATION CONFIGURATION
  # ==========================================

  # Pipeline event types that trigger SNS notifications.
  # STARTED — deployment began (log for audit trail)
  # SUCCEEDED — deployment complete (notify success)
  # FAILED — deployment failed (alert immediately)
  # SUPERSEDED — a newer commit pushed, old pipeline cancelled
  pipeline_notification_events = [
    "codepipeline-pipeline-pipeline-execution-started",
    "codepipeline-pipeline-pipeline-execution-succeeded",
    "codepipeline-pipeline-pipeline-execution-failed",
    "codepipeline-pipeline-pipeline-execution-superseded",
    "codepipeline-pipeline-stage-execution-failed",
    "codepipeline-pipeline-action-execution-failed"
  ]
}