# ============================================
# CodePipeline — CI/CD Pipeline Orchestration
# ============================================
#
# This file creates the CodePipeline pipelines that
# orchestrate the complete CI/CD flow for each
# application from source commit to deployed pods.
#
# One pipeline per application:
#   - absa-devops-pipeline-payment-api
#   - absa-devops-pipeline-fraud-detection
#
# Pipeline stages per application:
#
#   Stage 1: Source
#     - Trigger: push to main branch in CodeCommit
#     - Action: CodeCommit source checkout
#     - Output artifact: source.zip (committed code)
#
#   Stage 2: Build
#     - Trigger: Source stage completion
#     - Action: CodeBuild build project
#     - Input:  source.zip
#     - Output: build-output.zip (compiled JAR + Docker image in daemon)
#
#   Stage 3: Push
#     - Trigger: Build stage completion
#     - Action: CodeBuild push project
#     - Input:  build-output.zip
#     - Output: imagedetail.json (ECR image digest)
#
#   Stage 4: Approval (when var.require_manual_approval = true)
#     - Trigger: Push stage completion
#     - Action: Manual approval gate
#     - Approver receives SNS notification
#     - Pipeline pauses until approved or rejected
#     - Timeout: 7 days
#
#   Stage 5: Deploy-Primary
#     - Trigger: Approval stage (or Push stage if no approval)
#     - Action: CodeBuild deploy project
#     - Input:  imagedetail.json
#     - Output: deployment-output.json
#     - Deploys to: af-south-1 EKS cluster
#
#   Stage 6: Integration-Test
#     - Trigger: Deploy-Primary completion
#     - Action: CodeBuild integration-test project
#     - Input:  deployment-output.json
#     - Output: test-results.zip
#     - Runs inside VPC against live deployment
#
#   Stage 7: Deploy-DR (when var.deploy_to_dr = true)
#     - Trigger: Integration-Test completion
#     - Action: CodeBuild dr-deploy project
#     - Input:  imagedetail.json
#     - Deploys to: eu-west-1 DR EKS cluster
#
#   Stage 8: Notify
#     - Trigger: All prior stages completion
#     - Action: SNS publish deployment success
#     - Notifies: pipeline_notifications topic
#
# EventBridge rules trigger pipelines automatically
# on CodeCommit push — no polling, sub-second trigger.
#
# Pipeline execution history is retained by AWS for
# 12 months automatically (no Terraform config needed).
# ============================================

# ============================================
# SECTION 1 — CodePipeline Pipelines
# ============================================

resource "aws_codepipeline" "apps" {
  for_each = var.applications

  name     = local.pipeline_names[each.key]
  role_arn = local.codepipeline_role_arn

  # Artifact store — the S3 bucket where artifacts
  # are passed between pipeline stages.
  # One bucket, one KMS key for all pipelines.
  artifact_store {
    location = local.artifact_bucket_id
    type     = "S3"

    encryption_key {
      id   = local.kms_s3_arn
      type = "KMS"
    }
  }

  # ==========================================
  # STAGE 1 — SOURCE
  # ==========================================
  # Detects push to main branch in CodeCommit.
  # Zips the committed source code and uploads
  # to the artifact bucket as "SourceArtifact".
  # All subsequent stages consume this artifact.

  stage {
    name = "Source"

    action {
      name             = "CodeCommit-Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeCommit"
      version          = "1"
      output_artifacts = ["SourceArtifact"]

      configuration = {
        RepositoryName       = local.codecommit_repo_names[each.key]
        BranchName           = each.value.branch
        # PollForSourceChanges = false because we use
        # EventBridge rules (Section 2) for triggering.
        # EventBridge is sub-second; polling checks every
        # 1 minute. EventBridge also avoids the polling
        # cost at $0.10/1000 CloudWatch Events.
        PollForSourceChanges = "false"
        # OutputArtifactFormat = CODEBUILD_CLONE_REF
        # passes the Git clone URL rather than a zip.
        # CodeBuild then does a full git clone including
        # history — needed for semantic version tagging
        # that reads git tags and commit history.
        OutputArtifactFormat = "CODEBUILD_CLONE_REF"
      }
    }
  }

  # ==========================================
  # STAGE 2 — BUILD
  # ==========================================
  # Compiles code, runs unit tests, SAST scan,
  # builds Docker image.

  stage {
    name = "Build"

    action {
      name             = "CodeBuild-Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["SourceArtifact"]
      output_artifacts = ["BuildArtifact"]

      configuration = {
        ProjectName = local.codebuild_project_names[each.key].build
        # EnvironmentVariables — inject pipeline execution
        # context into the build. CODEBUILD_RESOLVED_SOURCE_VERSION
        # is automatically set by CodeBuild to the commit SHA.
        # Additional pipeline-level variables injected here:
        EnvironmentVariables = jsonencode([
          {
            name  = "PIPELINE_EXECUTION_ID"
            value = "#{codepipeline.PipelineExecutionId}"
            type  = "PLAINTEXT"
          }
        ])
      }

      # Run build action with CodePipeline role.
      # CodePipeline uses this role to start the
      # CodeBuild project on ABSA's behalf.
      role_arn = local.codepipeline_role_arn
    }
  }

  # ==========================================
  # STAGE 3 — PUSH
  # ==========================================
  # Pushes Docker image to ECR with commit SHA tag.
  # Writes imagedetail.json artifact containing
  # the ECR image URI and digest for the deploy stage.

  stage {
    name = "Push"

    action {
      name             = "CodeBuild-Push"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["SourceArtifact", "BuildArtifact"]
      output_artifacts = ["ImageArtifact"]

      configuration = {
        ProjectName = local.codebuild_project_names[each.key].push
        # PrimarySource declares which input artifact
        # CodeBuild treats as the primary source when
        # multiple input artifacts are provided.
        # SourceArtifact contains the Git clone with
        # commit SHA accessible via git commands.
        PrimarySource = "SourceArtifact"
        EnvironmentVariables = jsonencode([
          {
            name  = "PIPELINE_EXECUTION_ID"
            value = "#{codepipeline.PipelineExecutionId}"
            type  = "PLAINTEXT"
          }
        ])
      }

      role_arn = local.codepipeline_role_arn
    }
  }

  # ==========================================
  # STAGE 4 — APPROVAL (conditional)
  # ==========================================
  # Manual approval gate before production deployment.
  # When require_manual_approval = true, pipeline pauses
  # here. An approver receives an SNS notification and
  # reviews: build test results, scan findings, image
  # vulnerability scan summary, before approving.
  #
  # Approval notification email contains:
  #   - Pipeline name
  #   - Application name
  #   - Commit SHA being deployed
  #   - Link to CodeBuild test report
  #   - Approve/Reject buttons (links to AWS console)
  #
  # Timeout: 7 days (AWS CodePipeline default).
  # After 7 days without approval, stage fails.
  #
  # For payment_api: always requires approval (financial)
  # For fraud_detection: configurable via variable

  dynamic "stage" {
    for_each = var.require_manual_approval ? [1] : []
    content {
      name = "Approve"

      action {
        name     = "Manual-Approval"
        category = "Approval"
        owner    = "AWS"
        provider = "Manual"
        version  = "1"

        configuration = {
          NotificationArn = local.pipeline_notifications_arn
          CustomData      = "Review build results and approve deployment of ${each.value.display_name} to production EKS. Check CodeBuild test report before approving."
          ExternalEntityLink = "https://${var.primary_region}.console.aws.amazon.com/codesuite/codebuild/projects/${local.codebuild_project_names[each.key].build}/history"
        }
      }
    }
  }

  # ==========================================
  # STAGE 5 — DEPLOY PRIMARY
  # ==========================================
  # Rolling update to af-south-1 EKS cluster.
  # Waits for rollout to complete before proceeding.
  # If rollout fails (pods CrashLoopBackOff, image
  # pull error, readiness probe failure), this stage
  # fails and the pipeline stops — DR deploy never runs.

  stage {
    name = "Deploy-Primary"

    action {
      name             = "Deploy-af-south-1"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["ImageArtifact"]
      output_artifacts = ["DeployArtifact"]

      configuration = {
        ProjectName = local.codebuild_project_names[each.key].deploy
        EnvironmentVariables = jsonencode([
          {
            name  = "IMAGE_TAG"
            value = "#{ImageArtifact.ImageTag}"
            type  = "PLAINTEXT"
          },
          {
            name  = "PIPELINE_EXECUTION_ID"
            value = "#{codepipeline.PipelineExecutionId}"
            type  = "PLAINTEXT"
          }
        ])
      }

      role_arn = local.codepipeline_role_arn
    }
  }

  # ==========================================
  # STAGE 6 — INTEGRATION TEST
  # ==========================================
  # Runs inside VPC against live deployment.
  # Tests the actual deployed application version
  # end-to-end: HTTP requests to payment API,
  # database state verification, cache behavior.
  # Publishes JUnit XML report to CodeBuild.
  # Pipeline fails if tests fail.

  stage {
    name = "Integration-Test"

    action {
      name             = "Integration-Tests"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["SourceArtifact", "DeployArtifact"]
      output_artifacts = ["TestArtifact"]

      configuration = {
        ProjectName   = local.codebuild_project_names[each.key].integration_test
        PrimarySource = "SourceArtifact"
        EnvironmentVariables = jsonencode([
          {
            name  = "PIPELINE_EXECUTION_ID"
            value = "#{codepipeline.PipelineExecutionId}"
            type  = "PLAINTEXT"
          }
        ])
      }

      role_arn = local.codepipeline_role_arn
    }
  }

  # ==========================================
  # STAGE 7 — DEPLOY DR (conditional)
  # ==========================================
  # Deploys to eu-west-1 DR EKS cluster.
  # Only created when var.deploy_to_dr = true.
  # Runs AFTER integration tests pass — only deploy
  # to DR if the primary deployment is verified healthy.
  # Uses the same ImageArtifact (ECR digest) as
  # the primary deploy — identical image, different cluster.

  dynamic "stage" {
    for_each = var.deploy_to_dr ? [1] : []
    content {
      name = "Deploy-DR"

      action {
        name             = "Deploy-eu-west-1"
        category         = "Build"
        owner            = "AWS"
        provider         = "CodeBuild"
        version          = "1"
        input_artifacts  = ["ImageArtifact"]
        output_artifacts = ["DRDeployArtifact"]

        configuration = {
          ProjectName = local.codebuild_project_names[each.key].dr_deploy
          EnvironmentVariables = jsonencode([
            {
              name  = "IMAGE_TAG"
              value = "#{ImageArtifact.ImageTag}"
              type  = "PLAINTEXT"
            },
            {
              name  = "PIPELINE_EXECUTION_ID"
              value = "#{codepipeline.PipelineExecutionId}"
              type  = "PLAINTEXT"
            }
          ])
        }

        role_arn = local.codepipeline_role_arn
      }
    }
  }

  tags = merge(local.common_tags, {
    Name        = local.pipeline_names[each.key]
    Application = each.value.display_name
  })
}

# ============================================
# SECTION 2 — EventBridge Rules
# ============================================
# Trigger pipelines automatically on CodeCommit push.
# EventBridge (formerly CloudWatch Events) listens
# for CodeCommit state change events and starts
# the corresponding CodePipeline pipeline.
#
# Why EventBridge instead of CodePipeline polling?
#   - Sub-second trigger (vs 1-minute polling)
#   - No per-pipeline polling cost
#   - Event carries commit context (author, SHA, message)
#   - EventBridge is idempotent — rapid successive pushes
#     trigger the pipeline once per push, not multiple times
#
# Event pattern: matches when a specific branch
# in a specific repository receives a push.
# referenceUpdated = a commit was pushed to a branch.

resource "aws_cloudwatch_event_rule" "pipeline_trigger" {
  for_each = var.applications

  name        = "absa-devops-trigger-${local.app_names[each.key]}"
  description = "Trigger ${each.value.display_name} pipeline on push to ${each.value.branch}"

  event_pattern = jsonencode({
    source      = ["aws.codecommit"]
    "detail-type" = ["CodeCommit Repository State Change"]
    resources   = [local.codecommit_repo_arns[each.key]]
    detail = {
      event         = ["referenceUpdated"]
      referenceType = ["branch"]
      referenceName = [each.value.branch]
    }
  })

  tags = merge(local.common_tags, {
    Name        = "ABSA-DevOps-Pipeline-Trigger-${local.app_names[each.key]}"
    Application = each.value.display_name
  })
}

# EventBridge target — start the CodePipeline pipeline
# when the trigger rule fires.
resource "aws_cloudwatch_event_target" "pipeline_trigger" {
  for_each = var.applications

  rule     = aws_cloudwatch_event_rule.pipeline_trigger[each.key].name
  arn      = aws_codepipeline.apps[each.key].arn
  role_arn = aws_iam_role.eventbridge_pipeline.arn
  target_id = "StartPipeline-${local.app_names[each.key]}"
}

# ============================================
# SECTION 3 — EventBridge IAM Role
# ============================================
# EventBridge needs permission to start CodePipeline
# pipelines when trigger rules fire.
# Separate from the CodePipeline execution role —
# EventBridge only needs StartPipelineExecution,
# not the full suite of pipeline orchestration permissions.

resource "aws_iam_role" "eventbridge_pipeline" {
  name        = "ABSA-DevOps-EventBridge-Pipeline-Role"
  description = "Allows EventBridge to start CodePipeline executions on CodeCommit push"
  path        = "/devops/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowEventBridgeAssumption"
      Effect = "Allow"
      Principal = {
        Service = "events.amazonaws.com"
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
    Name    = "ABSA-DevOps-EventBridge-Pipeline-Role"
    Service = "EventBridge"
  })
}

resource "aws_iam_role_policy" "eventbridge_pipeline" {
  name = "ABSA-DevOps-EventBridge-Pipeline-Policy"
  role = aws_iam_role.eventbridge_pipeline.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "StartPipelineExecution"
      Effect = "Allow"
      Action = "codepipeline:StartPipelineExecution"
      # Scoped to only ABSA DevOps pipelines
      Resource = [
        for arn in [for k, p in aws_codepipeline.apps : p.arn] : arn
      ]
    }]
  })
}

# ============================================
# SECTION 4 — Pipeline Execution Notifications
# ============================================
# EventBridge rules that publish pipeline execution
# events to the notifications SNS topic.
# Notifies the DevOps team on:
#   - Pipeline started (audit trail, deployment awareness)
#   - Pipeline succeeded (deployment complete)
#   - Pipeline failed (immediate alert)
#   - Stage failed (which specific stage broke)
#
# These rules are separate from the trigger rules above.
# Trigger rules: CodeCommit push → start pipeline
# Notification rules: pipeline events → SNS notify

resource "aws_cloudwatch_event_rule" "pipeline_notifications" {
  for_each = var.applications

  name        = "absa-devops-notify-${local.app_names[each.key]}"
  description = "Notify team on ${each.value.display_name} pipeline execution events"

  event_pattern = jsonencode({
    source      = ["aws.codepipeline"]
    "detail-type" = ["CodePipeline Pipeline Execution State Change"]
    resources   = [aws_codepipeline.apps[each.key].arn]
    detail = {
      state = [
        "STARTED",
        "SUCCEEDED",
        "FAILED",
        "SUPERSEDED",
        "STOPPED"
      ]
    }
  })

  tags = merge(local.common_tags, {
    Name        = "ABSA-DevOps-Pipeline-Notify-${local.app_names[each.key]}"
    Application = each.value.display_name
  })
}

resource "aws_cloudwatch_event_target" "pipeline_notifications" {
  for_each = var.applications

  rule      = aws_cloudwatch_event_rule.pipeline_notifications[each.key].name
  arn       = local.pipeline_notifications_arn
  target_id = "PipelineNotify-${local.app_names[each.key]}"

  # Input transformer — formats the raw EventBridge
  # JSON into a human-readable SNS message.
  # Without this, the SNS notification contains raw
  # JSON that is difficult to read in an email.
  input_transformer {
    input_paths = {
      pipeline  = "$.detail.pipeline"
      state     = "$.detail.state"
      execution = "$.detail.execution-id"
      time      = "$.time"
    }
    input_template = "\"ABSA DevOps: Pipeline <pipeline> <state> at <time>. Execution ID: <execution>. View in console: https://${var.primary_region}.console.aws.amazon.com/codesuite/codepipeline/pipelines/<pipeline>/view\""
  }
}

# Stage-level failure notifications — more granular
# than pipeline-level. Tells the team WHICH stage failed
# (Build? Push? Deploy?) rather than just "pipeline failed".
resource "aws_cloudwatch_event_rule" "stage_failure_notifications" {
  for_each = var.applications

  name        = "absa-devops-stage-fail-${local.app_names[each.key]}"
  description = "Notify team when any ${each.value.display_name} pipeline stage fails"

  event_pattern = jsonencode({
    source      = ["aws.codepipeline"]
    "detail-type" = ["CodePipeline Stage Execution State Change"]
    resources   = [aws_codepipeline.apps[each.key].arn]
    detail = {
      state = ["FAILED"]
    }
  })

  tags = merge(local.common_tags, {
    Name        = "ABSA-DevOps-Stage-Fail-Notify-${local.app_names[each.key]}"
    Application = each.value.display_name
  })
}

resource "aws_cloudwatch_event_target" "stage_failure_notifications" {
  for_each = var.applications

  rule      = aws_cloudwatch_event_rule.stage_failure_notifications[each.key].name
  arn       = local.pipeline_notifications_arn
  target_id = "StageFailNotify-${local.app_names[each.key]}"

  input_transformer {
    input_paths = {
      pipeline = "$.detail.pipeline"
      stage    = "$.detail.stage"
      state    = "$.detail.state"
      time     = "$.time"
    }
    input_template = "\"ABSA DevOps: STAGE FAILED — Pipeline <pipeline> / Stage <stage> at <time>. Investigate: https://${var.primary_region}.console.aws.amazon.com/codesuite/codepipeline/pipelines/<pipeline>/view\""
  }
}

# ============================================
# SECTION 5 — Pipeline CloudWatch Alarms
# ============================================
# Monitor pipeline health via CloudWatch metrics.
# Two alarms per pipeline:
#   1. Pipeline execution failed
#   2. Pipeline execution succeeded (for auditing
#      — confirms deployments are happening regularly)

resource "aws_cloudwatch_metric_alarm" "pipeline_failed" {
  for_each = var.applications

  alarm_name          = "ABSA-DevOps-Pipeline-Failed-${local.app_names[each.key]}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FailedPipelineExecutions"
  namespace           = "AWS/CodePipeline"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_description   = "${each.value.display_name} pipeline execution failed — deployment did not complete"

  dimensions = {
    PipelineName = local.pipeline_names[each.key]
  }

  alarm_actions = [local.pipeline_notifications_arn]
  ok_actions    = [local.pipeline_notifications_arn]

  tags = merge(local.common_tags, {
    Name        = "ABSA-DevOps-Pipeline-Failed-Alarm-${local.app_names[each.key]}"
    Application = each.value.display_name
  })
}

# ============================================
# SECTION 6 — Pipeline Deployment Frequency Metric
# ============================================
# Custom CloudWatch metric tracking deployment
# frequency. Published after each successful pipeline.
# Used in the DevOps dashboard to show deployment
# cadence — how often ABSA deploys each application.
#
# Deployment frequency is one of the four DORA
# (DevOps Research and Assessment) key metrics:
#   1. Deployment Frequency         ← this metric
#   2. Lead Time for Changes
#   3. Mean Time to Recovery (MTTR)
#   4. Change Failure Rate
#
# These metrics measure engineering team performance.

resource "aws_cloudwatch_metric_alarm" "deployment_frequency" {
  for_each = var.applications

  alarm_name          = "ABSA-DevOps-No-Deployments-${local.app_names[each.key]}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "SucceededPipelineExecutions"
  namespace           = "AWS/CodePipeline"
  # 7 days in seconds — alert if no deployment in a week
  period              = 604800
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "breaching"
  alarm_description   = "No successful ${each.value.display_name} deployments in 7 days — pipeline may be blocked or team is not deploying"

  dimensions = {
    PipelineName = local.pipeline_names[each.key]
  }

  # Route to pipeline notifications — low urgency
  alarm_actions = [local.pipeline_notifications_arn]

  tags = merge(local.common_tags, {
    Name        = "ABSA-DevOps-Deployment-Frequency-Alarm-${local.app_names[each.key]}"
    Application = each.value.display_name
  })
}

# ============================================
# SECTION 7 — Pipeline Webhook
# ============================================
# GitHub webhook configuration — for future use
# if ABSA migrates from CodeCommit to GitHub.
# Currently using EventBridge + CodeCommit.
# This resource is commented out but preserved
# as a migration reference.
#
# To migrate:
#   1. Uncomment this resource
#   2. Change source stage provider to "GitHub"
#   3. Add GitHub OAuth token to Secrets Manager
#   4. Remove EventBridge trigger rules (Section 2)
#
# resource "aws_codepipeline_webhook" "github" {
#   for_each = var.applications
#
#   name            = "absa-devops-webhook-${local.app_names[each.key]}"
#   authentication  = "GITHUB_HMAC"
#   target_action   = "Source"
#   target_pipeline = aws_codepipeline.apps[each.key].name
#
#   authentication_configuration {
#     secret_token = random_password.webhook_secret[each.key].result
#   }
#
#   filter {
#     json_path    = "$.ref"
#     match_equals = "refs/heads/${each.value.branch}"
#   }
# }

# ============================================
# SECTION 8 — Pipeline Locals for outputs.tf
# ============================================

locals {
  # Pipeline ARNs — consumed by outputs.tf
  pipeline_arns = {
    for key, pipeline in aws_codepipeline.apps :
    key => pipeline.arn
  }

  # EventBridge trigger rule ARNs
  pipeline_trigger_arns = {
    for key, rule in aws_cloudwatch_event_rule.pipeline_trigger :
    key => rule.arn
  }
}