# ============================================
# S3 Artifacts — CodePipeline Artifact Storage
# ============================================
#
# CodePipeline uses S3 as the hand-off point between
# pipeline stages. When one stage completes it writes
# its output artifacts to S3. The next stage reads
# those artifacts from S3 as its input.
#
# What passes through this bucket between stages:
#
#   Source → Build:
#     The zipped source code from CodeCommit
#
#   Build → Push:
#     imagedefinitions.json — ECR image URI and tag
#     build-output.zip — compiled artifacts, test reports
#
#   Push → Deploy:
#     imagedetail.json — ECR image digest (sha256:xxx)
#
#   Deploy → Integration-Test:
#     deployment-output.json — rollout status
#
# All artifacts are encrypted with KMS.
# All artifacts expire according to lifecycle policy.
# One bucket for ALL pipelines — organized by prefix:
#   payment-api/<execution-id>/Source/
#   payment-api/<execution-id>/Build/
#   fraud-detection/<execution-id>/Source/
#   fraud-detection/<execution-id>/Build/
# ============================================

# ============================================
# SECTION 1 — Artifact Bucket
# ============================================

resource "aws_s3_bucket" "artifacts" {
  bucket        = local.artifact_bucket_name
  force_destroy = false

  tags = merge(local.common_tags, {
    Name    = "ABSA-DevOps-Pipeline-Artifacts"
    Purpose = "CodePipeline-Artifact-Store"
  })
}

# ============================================
# SECTION 2 — Bucket Versioning
# ============================================
# REQUIRED for CodePipeline artifact buckets.
# CodePipeline uses S3 object versioning internally
# to track artifact versions across pipeline executions.

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ============================================
# SECTION 3 — Server-Side Encryption
# ============================================

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = local.kms_s3_arn
    }
    bucket_key_enabled = true
  }
}

# ============================================
# SECTION 4 — Public Access Block
# ============================================

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ============================================
# SECTION 5 — Lifecycle Policy
# ============================================

resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  depends_on = [aws_s3_bucket_versioning.artifacts]

  rule {
    id     = "artifact-lifecycle"
    status = "Enabled"

    filter {
      prefix = ""
    }

    transition {
      days          = var.artifact_retention_days
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = 90
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    expiration {
      expired_object_delete_marker = true
    }
  }

  rule {
    id     = "incomplete-multipart-cleanup"
    status = "Enabled"

    filter {
      prefix = ""
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 3
    }
  }
}

# ============================================
# SECTION 6 — Bucket Policy
# ============================================

resource "aws_s3_bucket_policy" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCodePipelineAccess"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.codepipeline.arn
        }
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetBucketVersioning",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.artifacts.arn,
          "${aws_s3_bucket.artifacts.arn}/*"
        ]
      },
      {
        Sid    = "AllowCodeBuildAccess"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.codebuild.arn
        }
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:GetBucketVersioning",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.artifacts.arn,
          "${aws_s3_bucket.artifacts.arn}/*"
        ]
      },
      {
        Sid      = "DenyUnencryptedObjectUploads"
        Effect   = "Deny"
        Principal = "*"
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.artifacts.arn}/*"
        Condition = {
          StringNotEquals = {
            "s3:x-amz-server-side-encryption" = "aws:kms"
          }
        }
      },
      {
        Sid      = "EnforceSSLOnly"
        Effect   = "Deny"
        Principal = "*"
        Action   = "s3:*"
        Resource = [
          aws_s3_bucket.artifacts.arn,
          "${aws_s3_bucket.artifacts.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.artifacts]
}

# ============================================
# SECTION 7 — CloudWatch Alarm: Bucket Size
# ============================================

resource "aws_cloudwatch_metric_alarm" "artifact_bucket_size" {
  alarm_name          = "ABSA-DevOps-Artifact-Bucket-Size"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "BucketSizeBytes"
  namespace           = "AWS/S3"
  period              = 86400
  statistic           = "Average"
  threshold           = 10737418240
  treat_missing_data  = "notBreaching"
  alarm_description   = "DevOps artifact bucket exceeds 10GB — lifecycle policy may not be functioning"

  dimensions = {
    BucketName  = aws_s3_bucket.artifacts.id
    StorageType = "StandardStorage"
  }

  alarm_actions = [aws_sns_topic.pipeline_notifications.arn]

  tags = merge(local.common_tags, {
    Name = "ABSA-DevOps-Artifact-Bucket-Size-Alarm"
  })
}

# ============================================
# SECTION 8 — CodeCommit Repositories
# ============================================

resource "aws_codecommit_repository" "apps" {
  for_each = var.applications

  repository_name = local.codecommit_repo_names[each.key]
  description     = "${each.value.display_name} source code repository"
  default_branch  = each.value.branch

  tags = merge(local.common_tags, {
    Name        = "ABSA-DevOps-Repo-${local.app_names[each.key]}"
    Application = each.value.display_name
  })
}

# ============================================
# SECTION 9 — CodeCommit Notification Rules
# ============================================

resource "aws_codestarnotifications_notification_rule" "codecommit" {
  for_each = var.applications

  name        = "absa-devops-repo-${local.app_names[each.key]}-notifications"
  detail_type = "FULL"
  resource    = aws_codecommit_repository.apps[each.key].arn

  event_type_ids = [
    "codecommit-repository-branches-and-tags-created",
    "codecommit-repository-branches-and-tags-updated",
    "codecommit-repository-branches-and-tags-deleted",
    "codecommit-repository-pull-request-created",
    "codecommit-repository-pull-request-merged",
    "codecommit-repository-comments-on-commits",
  ]

  target {
    address = aws_sns_topic.pipeline_notifications.arn
  }

  tags = merge(local.common_tags, {
    Name        = "ABSA-DevOps-Repo-Notifications-${local.app_names[each.key]}"
    Application = each.value.display_name
  })
}

# ============================================
# SECTION 10 — Pipeline Notifications SNS Topic
# ============================================

resource "aws_sns_topic" "pipeline_notifications" {
  name              = "absa-devops-pipeline-notifications"
  kms_master_key_id = local.kms_s3_arn

  tags = merge(local.common_tags, {
    Name = "ABSA-DevOps-Pipeline-Notifications"
  })
}

resource "aws_sns_topic_policy" "pipeline_notifications" {
  arn = aws_sns_topic.pipeline_notifications.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCodeStarNotificationsPublish"
        Effect = "Allow"
        Principal = {
          Service = "codestar-notifications.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.pipeline_notifications.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AllowCodePipelinePublish"
        Effect = "Allow"
        Principal = {
          Service = "codepipeline.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.pipeline_notifications.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AllowEventBridgePublish"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.pipeline_notifications.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

resource "aws_sns_topic_subscription" "devops_email" {
  topic_arn = aws_sns_topic.pipeline_notifications.arn
  protocol  = "email"
  endpoint  = var.pipeline_notification_email
}

# ============================================
# SECTION 11 — Locals for other files
# ============================================

locals {
  artifact_bucket_arn  = aws_s3_bucket.artifacts.arn
  artifact_bucket_id   = aws_s3_bucket.artifacts.id

  codecommit_repo_arns = {
    for key, repo in aws_codecommit_repository.apps :
    key => repo.arn
  }

  codecommit_clone_urls_http = {
    for key, repo in aws_codecommit_repository.apps :
    key => repo.clone_url_http
  }

  pipeline_notifications_arn = aws_sns_topic.pipeline_notifications.arn
}