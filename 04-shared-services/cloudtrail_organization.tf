# ============================================
# Organization CloudTrail — Central Audit Trail
# ============================================

# S3 Bucket for CloudTrail Logs
resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket        = local.cloudtrail_bucket
  force_destroy = false

  tags = merge(local.common_tags, {
    Name = "ABSA-CloudTrail-Logs"
  })
}

resource "aws_s3_bucket_public_access_block" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    id     = "transition-to-glacier"
    status = "Enabled"

    transition {
      days          = var.s3_log_archive_retention_days
      storage_class = "GLACIER"
    }

    expiration {
      days = var.s3_log_archive_retention_days + var.s3_log_archive_glacier_retention_days
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail_logs.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Sid    = "AllowCloudTrailRead"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail_logs.arn
      }
    ]
  })
}

# Organization Trail — Logs ALL accounts
resource "aws_cloudtrail" "organization" {
  name                          = "ABSA-Organization-Trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail_logs.id
  include_global_service_events = true
  is_multi_region_trail         = true
  is_organization_trail         = true
  enable_log_file_validation    = true

  # KMS encryption
  kms_key_id = local.kms_cloudtrail_arn

  # CloudWatch Logs integration
  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_cloudwatch.arn

  # Event selectors — Log management + data events
  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::absa-*"]
    }
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail_logs]

  tags = merge(local.common_tags, {
    Name = "ABSA-Organization-Trail"
  })
}

# CloudWatch Log Group for CloudTrail
resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/aws/cloudtrail/ABSA-Organization-Trail"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "ABSA-CloudTrail-Log-Group"
  })
}

# IAM Role for CloudTrail to write to CloudWatch
resource "aws_iam_role" "cloudtrail_cloudwatch" {
  name = "ABSA-CloudTrail-CloudWatch-Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "ABSA-CloudTrail-CloudWatch-Role"
  })
}

resource "aws_iam_role_policy" "cloudtrail_cloudwatch" {
  name = "ABSA-CloudTrail-CloudWatch-Policy"
  role = aws_iam_role.cloudtrail_cloudwatch.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
      }
    ]
  })
}