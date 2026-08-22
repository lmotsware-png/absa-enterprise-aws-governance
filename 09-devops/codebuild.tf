# ============================================
# CodeBuild Projects — Build, Push, Deploy, Test
# ============================================
#
# This file creates CodeBuild projects for every
# stage of the pipeline for every application.
#
# Projects per application:
#
#   1. BUILD project
#      - Compiles application source code
#      - Runs unit tests with JUnit reporting
#      - Runs SAST (Semgrep) security scan
#      - Builds Docker image
#      - Outputs: built image in Docker daemon,
#                 test reports, scan results
#
#   2. PUSH project
#      - Authenticates to ECR
#      - Tags image with commit SHA + semantic version
#      - Pushes to primary ECR (af-south-1)
#      - Reads ECR scan findings post-push
#      - Outputs: imagedetail.json with digest
#
#   3. DEPLOY project (primary af-south-1)
#      - Generates kubeconfig for primary EKS
#      - Runs kubectl set image (rolling update)
#      - Waits for rollout to complete
#      - Verifies pod health post-deploy
#      - Outputs: deployment-output.json
#
#   4. DR-DEPLOY project (eu-west-1)
#      - Same as DEPLOY but targets DR EKS cluster
#      - Runs only when var.deploy_to_dr = true
#      - Uses DR region provider for CodeBuild
#
#   5. INTEGRATION-TEST project
#      - Runs inside VPC to reach Aurora + Redis
#      - Executes integration test suite against
#        the newly deployed application version
#      - Publishes JUnit test results as CodeBuild report
#      - Fails pipeline if tests fail
#
# All projects share:
#   - Same CodeBuild role (local.codebuild_role_arn)
#   - Same build environment image (var.codebuild_image)
#   - Same artifact bucket (local.artifact_bucket_id)
#   - KMS-encrypted artifacts
#   - CloudWatch logs to pre-created log groups
#
# VPC placement:
#   BUILD:            NO VPC (no internal resource access needed)
#   PUSH:             NO VPC (ECR is public endpoint / VPC endpoint)
#   DEPLOY:           NO VPC (EKS API is public endpoint)
#   DR-DEPLOY:        NO VPC (DR EKS API is public endpoint)
#   INTEGRATION-TEST: YES VPC (needs Aurora + Redis access)
# ============================================

# ============================================
# SECTION 1 — BUILD Projects
# ============================================
# Compiles code, runs unit tests, runs SAST scan,
# builds Docker image.
# Buildspec: buildspec_<app>.yml in the repository root.
# The actual buildspec content is in:
#   buildspec_payment_api.yml
#   buildspec_fraud_detection.yml
# Those files are explained separately.

resource "aws_codebuild_project" "build" {
  for_each = var.applications

  name          = local.codebuild_project_names[each.key].build
  description   = "Build, unit test, and Docker image creation for ${each.value.display_name}"
  build_timeout = each.value.build_timeout
  service_role  = local.codebuild_role_arn

  # Artifact configuration — CodePipeline manages artifact
  # passing between stages. Type = CODEPIPELINE means
  # CodeBuild reads input from and writes output to
  # the pipeline's artifact store (the S3 bucket).
  artifacts {
    type = "CODEPIPELINE"
  }

  # Cache configuration — speed up builds by caching
  # Maven/Gradle dependencies between runs.
  # S3 cache: first build downloads all dependencies,
  # subsequent builds restore from cache.
  # Reduces build time from ~8 minutes to ~3 minutes
  # for a typical Java application.
  cache {
    type     = "S3"
    location = "${local.artifact_bucket_id}/cache/${local.app_names[each.key]}/build"
  }

  environment {
    compute_type                = each.value.build_compute_type
    image                       = var.codebuild_image
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    # privileged_mode = true is REQUIRED for Docker builds.
    # Without this the Docker daemon is inaccessible and
    # 'docker build' fails with "permission denied".
    privileged_mode = var.codebuild_privileged_mode

    # Environment variables injected into every build.
    # Buildspec files reference these as $VARIABLE_NAME.

    environment_variable {
      name  = "APP_NAME"
      value = local.app_names[each.key]
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "ECR_REPOSITORY_URI"
      value = local.ecr_repository_urls[each.key]
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = data.aws_caller_identity.current.account_id
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "PRIMARY_REGION"
      value = var.primary_region
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "K8S_NAMESPACE"
      value = each.value.k8s_namespace
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "K8S_DEPLOYMENT"
      value = each.value.k8s_deployment
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "K8S_CONTAINER"
      value = each.value.k8s_container
      type  = "PLAINTEXT"
    }

    # SEMGREP_RULES — SAST scanner ruleset.
    # Buildspec runs: semgrep --config $SEMGREP_RULES src/
    environment_variable {
      name  = "SEMGREP_RULES"
      value = var.semgrep_rules
      type  = "PLAINTEXT"
    }

    # SONAR_TOKEN — read from Secrets Manager if
    # SonarQube scanning is enabled.
    # Type = SECRETS_MANAGER means CodeBuild calls
    # Secrets Manager at build start to resolve the value.
    # The secret value is never in plaintext in the
    # CodeBuild project configuration or build logs.
    dynamic "environment_variable" {
      for_each = var.enable_sonar_scan ? [1] : []
      content {
        name  = "SONAR_TOKEN"
        value = "absa/devops/sonar-token"
        type  = "SECRETS_MANAGER"
      }
    }
  }

  # Buildspec location — the buildspec file lives in
  # the application's source repository, not inline here.
  # Each application has its own buildspec with app-specific
  # build commands (Maven vs pip, JUnit vs pytest).
  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec_${replace(each.key, "_", "")}.yml"
  }

  # CloudWatch logs — write to pre-created log group
  # from iam_roles.tf with 90-day retention.
  logs_config {
    cloudwatch_logs {
      group_name  = "/aws/codebuild/${local.codebuild_project_names[each.key].build}"
      stream_name = "build-log"
      status      = "ENABLED"
    }

    # S3 logs — archive raw build logs to artifact bucket
    # as a complement to CloudWatch structured logs.
    # Useful for: log analysis, compliance archival,
    # log downloads without CloudWatch Insights.
    s3_logs {
      location = "${local.artifact_bucket_id}/build-logs/${local.app_names[each.key]}/build"
      status   = "ENABLED"

      encryption_disabled = false
    }
  }

  tags = merge(local.common_tags, {
    Name        = "ABSA-DevOps-Build-${local.app_names[each.key]}"
    Application = each.value.display_name
    Stage       = "Build"
  })
}

# ============================================
# SECTION 2 — PUSH Projects
# ============================================
# Authenticates to ECR, tags image, pushes image,
# checks scan findings.
# No VPC needed — ECR accessed via VPC endpoint
# or through internet (ECR is a regional public service).

resource "aws_codebuild_project" "push" {
  for_each = var.applications

  name          = local.codebuild_project_names[each.key].push
  description   = "Docker image push to ECR for ${each.value.display_name}"
  build_timeout = 10
  service_role  = local.codebuild_role_arn

  artifacts {
    type = "CODEPIPELINE"
  }

  cache {
    type = "NO_CACHE"
  }

  environment {
    # Push stage needs medium compute — image layers
    # can be large and network transfer benefits from
    # more CPU for compression operations.
    compute_type                = "BUILD_GENERAL1_MEDIUM"
    image                       = var.codebuild_image
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    # privileged_mode required to run docker commands
    # for ECR authentication and image tagging.
    privileged_mode             = true

    environment_variable {
      name  = "APP_NAME"
      value = local.app_names[each.key]
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "ECR_REPOSITORY_URI"
      value = local.ecr_repository_urls[each.key]
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "ECR_REPOSITORY_ARN"
      value = local.ecr_repository_arns[each.key]
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = data.aws_caller_identity.current.account_id
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "PRIMARY_REGION"
      value = var.primary_region
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "DR_REGION"
      value = var.dr_region
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "ECR_PUSH_ROLE_ARN"
      value = local.ecr_push_role_arn
      type  = "PLAINTEXT"
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec_push.yml"
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/aws/codebuild/${local.codebuild_project_names[each.key].push}"
      stream_name = "push-log"
      status      = "ENABLED"
    }

    s3_logs {
      location            = "${local.artifact_bucket_id}/build-logs/${local.app_names[each.key]}/push"
      status              = "ENABLED"
      encryption_disabled = false
    }
  }

  tags = merge(local.common_tags, {
    Name        = "ABSA-DevOps-Push-${local.app_names[each.key]}"
    Application = each.value.display_name
    Stage       = "Push"
  })
}

# ============================================
# SECTION 3 — DEPLOY Projects (Primary EKS)
# ============================================
# Generates kubeconfig, runs kubectl set image,
# waits for rollout, verifies pod health.
# No VPC needed — EKS API server has a public endpoint
# with IAM authentication (no VPC endpoint required
# for control plane access from CodeBuild).

resource "aws_codebuild_project" "deploy" {
  for_each = var.applications

  name          = local.codebuild_project_names[each.key].deploy
  description   = "Deploy ${each.value.display_name} to primary EKS cluster"
  build_timeout = 15
  service_role  = local.codebuild_role_arn

  artifacts {
    type = "CODEPIPELINE"
  }

  cache {
    type = "NO_CACHE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = var.codebuild_image
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    # No privileged_mode needed — deploy stage runs
    # kubectl commands, not Docker build commands.
    privileged_mode             = false

    environment_variable {
      name  = "APP_NAME"
      value = local.app_names[each.key]
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "ECR_REPOSITORY_URI"
      value = local.ecr_repository_urls[each.key]
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "EKS_CLUSTER_NAME"
      value = local.primary_eks_cluster_name
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "AWS_REGION"
      value = var.primary_region
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "K8S_NAMESPACE"
      value = each.value.k8s_namespace
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "K8S_DEPLOYMENT"
      value = each.value.k8s_deployment
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "K8S_CONTAINER"
      value = each.value.k8s_container
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "EKS_DEPLOY_ROLE_ARN"
      value = local.eks_deploy_role_arn
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "MIN_HEALTHY_PERCENT"
      value = tostring(each.value.min_healthy_percent)
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "MAX_SURGE_PERCENT"
      value = tostring(each.value.max_surge_percent)
      type  = "PLAINTEXT"
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec_deploy.yml"
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/aws/codebuild/${local.codebuild_project_names[each.key].deploy}"
      stream_name = "deploy-log"
      status      = "ENABLED"
    }

    s3_logs {
      location            = "${local.artifact_bucket_id}/build-logs/${local.app_names[each.key]}/deploy"
      status              = "ENABLED"
      encryption_disabled = false
    }
  }

  tags = merge(local.common_tags, {
    Name        = "ABSA-DevOps-Deploy-${local.app_names[each.key]}"
    Application = each.value.display_name
    Stage       = "Deploy-Primary"
  })
}

# ============================================
# SECTION 4 — DR-DEPLOY Projects (eu-west-1 EKS)
# ============================================
# Identical to DEPLOY but targets the DR EKS cluster.
# Created only when var.deploy_to_dr = true.
# Uses the DR provider because CodeBuild projects
# are regional resources — the DR deploy project
# lives in eu-west-1 to minimize cross-region
# kubectl latency during deployment.

resource "aws_codebuild_project" "dr_deploy" {
  for_each = var.deploy_to_dr ? var.applications : {}

  provider = aws.dr

  name          = local.codebuild_project_names[each.key].dr_deploy
  description   = "Deploy ${each.value.display_name} to DR EKS cluster in eu-west-1"
  build_timeout = 15
  service_role  = local.codebuild_role_arn

  artifacts {
    type = "CODEPIPELINE"
  }

  cache {
    type = "NO_CACHE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = var.codebuild_image
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = false

    environment_variable {
      name  = "APP_NAME"
      value = local.app_names[each.key]
      type  = "PLAINTEXT"
    }

    # DR ECR URI — images replicated from primary ECR
    environment_variable {
      name  = "ECR_REPOSITORY_URI"
      value = local.dr_ecr_repository_uris[each.key]
      type  = "PLAINTEXT"
    }

    # DR cluster name — target for kubectl commands
    environment_variable {
      name  = "EKS_CLUSTER_NAME"
      value = local.dr_eks_cluster_name != null ? local.dr_eks_cluster_name : ""
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "AWS_REGION"
      value = var.dr_region
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "K8S_NAMESPACE"
      value = each.value.k8s_namespace
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "K8S_DEPLOYMENT"
      value = each.value.k8s_deployment
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "K8S_CONTAINER"
      value = each.value.k8s_container
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "EKS_DEPLOY_ROLE_ARN"
      value = local.eks_deploy_role_arn
      type  = "PLAINTEXT"
    }

    # DR deployments use SECONDARY rolling update strategy:
    # Faster rollout acceptable — DR cluster may have
    # fewer nodes than primary so surge headroom differs
    environment_variable {
      name  = "MIN_HEALTHY_PERCENT"
      value = "50"
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "MAX_SURGE_PERCENT"
      value = "150"
      type  = "PLAINTEXT"
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec_deploy.yml"
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/aws/codebuild/${local.codebuild_project_names[each.key].dr_deploy}"
      stream_name = "dr-deploy-log"
      status      = "ENABLED"
    }

    s3_logs {
      location            = "${local.artifact_bucket_id}/build-logs/${local.app_names[each.key]}/dr-deploy"
      status              = "ENABLED"
      encryption_disabled = false
    }
  }

  tags = merge(local.common_tags, {
    Name        = "ABSA-DevOps-DR-Deploy-${local.app_names[each.key]}"
    Application = each.value.display_name
    Stage       = "Deploy-DR"
  })
}

# ============================================
# SECTION 5 — INTEGRATION-TEST Projects
# ============================================
# Runs inside the VPC to access Aurora and Redis.
# Executes the application's integration test suite
# against the live deployment.
# Publishes JUnit XML results as CodeBuild reports.
# Fails the pipeline if any integration test fails.
#
# VPC placement gives access to:
#   - Aurora reader endpoint (10.1.21.x) for DB tests
#   - Redis primary endpoint (10.1.21.x) for cache tests
#   - Internal ALB endpoint for API endpoint tests
#
# This stage runs AFTER primary deployment succeeds.
# If tests fail, pipeline fails — the deployment
# already happened, but the integration test failure
# triggers an alert and blocks DR deployment.

resource "aws_codebuild_project" "integration_test" {
  for_each = var.applications

  name          = local.codebuild_project_names[each.key].integration_test
  description   = "Integration tests for ${each.value.display_name} against live deployment"
  build_timeout = 20
  service_role  = local.codebuild_role_arn

  artifacts {
    type = "CODEPIPELINE"
  }

  cache {
    type = "NO_CACHE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_MEDIUM"
    image                       = var.codebuild_image
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = false

    environment_variable {
      name  = "APP_NAME"
      value = local.app_names[each.key]
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "K8S_NAMESPACE"
      value = each.value.k8s_namespace
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "EKS_CLUSTER_NAME"
      value = local.primary_eks_cluster_name
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "AWS_REGION"
      value = var.primary_region
      type  = "PLAINTEXT"
    }

    # RDS reader endpoint for integration tests.
    # Read-only — tests cannot accidentally write
    # production data through this connection.
    environment_variable {
      name  = "RDS_READER_ENDPOINT"
      value = local.primary_rds_reader_endpoint
      type  = "PLAINTEXT"
    }

    # DB credentials read from Secrets Manager
    # at test runtime — not in plaintext here.
    environment_variable {
      name  = "DB_SECRET_ARN"
      value = "absa/production/rds-credentials"
      type  = "SECRETS_MANAGER"
    }

    # Container port for health check verification
    environment_variable {
      name  = "CONTAINER_PORT"
      value = tostring(each.value.container_port)
      type  = "PLAINTEXT"
    }
  }

  # VPC CONFIGURATION — placed inside the production VPC
  # app tier to reach Aurora (10.1.21.x) and Redis.
  # Uses the same subnets and security group as EKS nodes
  # so the Week 3 security group rules permit access
  # to the data tier services.
  vpc_config {
    vpc_id             = local.vpc_id
    subnets            = local.app_subnet_ids
    security_group_ids = [local.app_security_group_id]
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec_integration_test.yml"
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/aws/codebuild/${local.codebuild_project_names[each.key].integration_test}"
      stream_name = "integration-test-log"
      status      = "ENABLED"
    }

    s3_logs {
      location            = "${local.artifact_bucket_id}/build-logs/${local.app_names[each.key]}/integration-test"
      status              = "ENABLED"
      encryption_disabled = false
    }
  }

  tags = merge(local.common_tags, {
    Name        = "ABSA-DevOps-IntTest-${local.app_names[each.key]}"
    Application = each.value.display_name
    Stage       = "Integration-Test"
  })
}

# ============================================
# SECTION 6 — CodeBuild CloudWatch Alarms
# ============================================
# Monitor build failure rates across all projects.
# Two alarms per application:
#   1. Build failure — the BUILD stage failed
#      (compile error, unit test failure, SAST finding)
#   2. Deploy failure — the DEPLOY stage failed
#      (kubectl error, pod not healthy after rollout)

resource "aws_cloudwatch_metric_alarm" "build_failures" {
  for_each = var.applications

  alarm_name          = "ABSA-DevOps-Build-Failure-${local.app_names[each.key]}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FailedBuilds"
  namespace           = "AWS/CodeBuild"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_description   = "${each.value.display_name} build stage failed — check CodeBuild logs"

  dimensions = {
    ProjectName = local.codebuild_project_names[each.key].build
  }

  alarm_actions = [local.pipeline_notifications_arn]

  tags = merge(local.common_tags, {
    Name        = "ABSA-DevOps-Build-Failure-Alarm-${local.app_names[each.key]}"
    Application = each.value.display_name
  })
}

resource "aws_cloudwatch_metric_alarm" "deploy_failures" {
  for_each = var.applications

  alarm_name          = "ABSA-DevOps-Deploy-Failure-${local.app_names[each.key]}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FailedBuilds"
  namespace           = "AWS/CodeBuild"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_description   = "${each.value.display_name} deploy stage failed — pods may be in CrashLoopBackOff"

  dimensions = {
    ProjectName = local.codebuild_project_names[each.key].deploy
  }

  alarm_actions = [local.pipeline_notifications_arn]

  tags = merge(local.common_tags, {
    Name        = "ABSA-DevOps-Deploy-Failure-Alarm-${local.app_names[each.key]}"
    Application = each.value.display_name
  })
}

# ============================================
# SECTION 7 — CodeBuild Dashboard
# ============================================
# Single CloudWatch dashboard showing build metrics
# across all applications and pipeline stages.

resource "aws_cloudwatch_dashboard" "devops" {
  dashboard_name = "ABSA-DevOps-Pipeline-Health"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "# ABSA DevOps Pipeline Health — af-south-1 | Applications: ${join(", ", [for k, v in var.applications : v.display_name])}"
        }
      },

      # Build success rate — payment-api
      {
        type   = "metric"
        x      = 0
        y      = 1
        width  = 12
        height = 6
        properties = {
          title  = "Payment API — Build Metrics"
          view   = "timeSeries"
          stat   = "Sum"
          period = 3600
          metrics = [
            ["AWS/CodeBuild", "SucceededBuilds", "ProjectName", local.codebuild_project_names["payment_api"].build, { label = "Succeeded" }],
            ["AWS/CodeBuild", "FailedBuilds", "ProjectName", local.codebuild_project_names["payment_api"].build, { label = "Failed", color = "#ff0000" }],
          ]
        }
      },

      # Build success rate — fraud-detection
      {
        type   = "metric"
        x      = 12
        y      = 1
        width  = 12
        height = 6
        properties = {
          title  = "Fraud Detection — Build Metrics"
          view   = "timeSeries"
          stat   = "Sum"
          period = 3600
          metrics = [
            ["AWS/CodeBuild", "SucceededBuilds", "ProjectName", local.codebuild_project_names["fraud_detection"].build, { label = "Succeeded" }],
            ["AWS/CodeBuild", "FailedBuilds", "ProjectName", local.codebuild_project_names["fraud_detection"].build, { label = "Failed", color = "#ff0000" }],
          ]
        }
      },

      # Build duration trends
      {
        type   = "metric"
        x      = 0
        y      = 7
        width  = 12
        height = 6
        properties = {
          title  = "Build Duration (seconds)"
          view   = "timeSeries"
          stat   = "Average"
          period = 3600
          metrics = [
            ["AWS/CodeBuild", "Duration", "ProjectName", local.codebuild_project_names["payment_api"].build, { label = "Payment API Build" }],
            ["AWS/CodeBuild", "Duration", "ProjectName", local.codebuild_project_names["fraud_detection"].build, { label = "Fraud Detection Build" }],
          ]
        }
      },

      # Deploy duration trends
      {
        type   = "metric"
        x      = 12
        y      = 7
        width  = 12
        height = 6
        properties = {
          title  = "Deploy Duration (seconds)"
          view   = "timeSeries"
          stat   = "Average"
          period = 3600
          metrics = [
            ["AWS/CodeBuild", "Duration", "ProjectName", local.codebuild_project_names["payment_api"].deploy, { label = "Payment API Deploy" }],
            ["AWS/CodeBuild", "Duration", "ProjectName", local.codebuild_project_names["fraud_detection"].deploy, { label = "Fraud Detection Deploy" }],
          ]
        }
      },

      # Alarm status
      {
        type   = "alarm"
        x      = 0
        y      = 13
        width  = 24
        height = 3
        properties = {
          title = "Pipeline Alarm Status"
          alarms = concat(
            [for k, v in var.applications : aws_cloudwatch_metric_alarm.build_failures[k].arn],
            [for k, v in var.applications : aws_cloudwatch_metric_alarm.deploy_failures[k].arn]
          )
        }
      }
    ]
  })
}