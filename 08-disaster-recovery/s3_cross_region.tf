# ============================================
# S3 Cross-Region Replication — DR Compliance Data
# ============================================
# This file:
# 1. Creates KMS key for DR S3 encryption in eu-west-1
# 2. Creates destination buckets in eu-west-1 (CloudTrail + Config)
# 3. Creates IAM role for S3 replication service
# 4. Configures replication rules on primary (af-south-1) source buckets
# 5. Creates CloudWatch alarms monitoring replication health
#
# Prerequisites (verified via locals.tf remote state reads):
#   - Week 4: cloudtrail bucket has versioning enabled
#   - Week 4: config bucket has versioning enabled
#   - Week 4: bucket ARNs exported as outputs
# ============================================

# ============================================
# KMS Key for DR Region — S3 Encryption
# ============================================

resource "aws_kms_key" "dr_s3" {
  provider = aws.dr

  description             = "KMS key for DR S3 bucket encryption in eu-west-1"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-S3-KMS-Key"
  })
}

resource "aws_kms_alias" "dr_s3" {
  provider = aws.dr

  name          = "alias/absa-dr-s3-encryption"
  target_key_id = aws_kms_key.dr_s3.key_id
}

# ============================================
# DR CloudTrail Logs Bucket — eu-west-1
# Destination for S3 CRR from primary CloudTrail bucket
# ============================================

resource "aws_s3_bucket" "dr_cloudtrail" {
  provider = aws.dr

  bucket        = "absa-dr-cloudtrail-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = false

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-CloudTrail-Logs"
  })
}

# Versioning — REQUIRED for S3 CRR destination bucket
resource "aws_s3_bucket_versioning" "dr_cloudtrail" {
  provider = aws.dr
  bucket   = aws_s3_bucket.dr_cloudtrail.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption using DR KMS key
resource "aws_s3_bucket_server_side_encryption_configuration" "dr_cloudtrail" {
  provider = aws.dr
  bucket   = aws_s3_bucket.dr_cloudtrail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.dr_s3.arn
    }
    bucket_key_enabled = true
  }
}

# Maximum public access blocking
resource "aws_s3_bucket_public_access_block" "dr_cloudtrail" {
  provider = aws.dr
  bucket   = aws_s3_bucket.dr_cloudtrail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle policy — transition replicated logs to cheaper storage tiers
resource "aws_s3_bucket_lifecycle_configuration" "dr_cloudtrail" {
  provider = aws.dr
  bucket   = aws_s3_bucket.dr_cloudtrail.id

  rule {
    id     = "cloudtrail-dr-lifecycle"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 2555  # 7 years — PCI-DSS audit retention
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# ============================================
# DR Config Logs Bucket — eu-west-1
# Destination for S3 CRR from primary Config bucket
# ============================================

resource "aws_s3_bucket" "dr_config" {
  provider = aws.dr

  bucket        = "absa-dr-config-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = false

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-Config-Logs"
  })
}

# Versioning — REQUIRED for S3 CRR destination bucket
resource "aws_s3_bucket_versioning" "dr_config" {
  provider = aws.dr
  bucket   = aws_s3_bucket.dr_config.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption using DR KMS key
resource "aws_s3_bucket_server_side_encryption_configuration" "dr_config" {
  provider = aws.dr
  bucket   = aws_s3_bucket.dr_config.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.dr_s3.arn
    }
    bucket_key_enabled = true
  }
}

# Maximum public access blocking
resource "aws_s3_bucket_public_access_block" "dr_config" {
  provider = aws.dr
  bucket   = aws_s3_bucket.dr_config.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle policy
resource "aws_s3_bucket_lifecycle_configuration" "dr_config" {
  provider = aws.dr
  bucket   = aws_s3_bucket.dr_config.id

  rule {
    id     = "config-dr-lifecycle"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 2555
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# ============================================
# IAM Role for S3 Cross-Region Replication
# ============================================
# This role is assumed by the S3 service (not a regional service)
# to perform replication on behalf of the source buckets.
# Lives in the primary region (no provider = uses default af-south-1).

resource "aws_iam_role" "s3_replication" {
  name        = "ABSA-S3-CRR-Replication-Role"
  description = "Allows S3 to replicate objects from primary to DR buckets"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(local.common_tags, {
    Name = "ABSA-S3-CRR-Replication-Role"
  })
}

resource "aws_iam_role_policy" "s3_replication" {
  name = "ABSA-S3-CRR-Replication-Policy"
  role = aws_iam_role.s3_replication.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Read from source CloudTrail bucket
      {
        Sid    = "ReadSourceCloudTrail"
        Effect = "Allow"
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Resource = "arn:aws:s3:::${local.cloudtrail_bucket_name}"
      },
      # Read source CloudTrail objects
      {
        Sid    = "ReadSourceCloudTrailObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging"
        ]
        Resource = "arn:aws:s3:::${local.cloudtrail_bucket_name}/*"
      },
      # Read from source Config bucket
      {
        Sid    = "ReadSourceConfig"
        Effect = "Allow"
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Resource = "arn:aws:s3:::${local.config_bucket_name}"
      },
      # Read source Config objects
      {
        Sid    = "ReadSourceConfigObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging"
        ]
        Resource = "arn:aws:s3:::${local.config_bucket_name}/*"
      },
      # Write to DR CloudTrail destination bucket
      {
        Sid    = "WriteDestinationCloudTrail"
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags",
          "s3:GetObjectVersionTagging",
          "s3:ObjectOwnerOverrideToBucketOwner"
        ]
        Resource = "${aws_s3_bucket.dr_cloudtrail.arn}/*"
      },
      # Write to DR Config destination bucket
      {
        Sid    = "WriteDestinationConfig"
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags",
          "s3:GetObjectVersionTagging",
          "s3:ObjectOwnerOverrideToBucketOwner"
        ]
        Resource = "${aws_s3_bucket.dr_config.arn}/*"
      },
      # KMS permissions — decrypt source objects and encrypt destination objects
      {
        Sid    = "DecryptSourceKMS"
        Effect = "Allow"
        Action = ["kms:Decrypt"]
        Resource = local.kms_s3_arn
        Condition = {
          StringLike = {
            "kms:ViaService" = "s3.${var.primary_region}.amazonaws.com"
          }
        }
      },
      {
        Sid    = "EncryptDestinationKMS"
        Effect = "Allow"
        Action = ["kms:GenerateDataKey"]
        Resource = aws_kms_key.dr_s3.arn
        Condition = {
          StringLike = {
            "kms:ViaService" = "s3.${var.dr_region}.amazonaws.com"
          }
        }
      }
    ]
  })
}

# ============================================
# DR Bucket Policies — Allow Replication Role to Write
# The destination buckets must explicitly authorize the replication role
# using aws:SourceAccount to prevent cross-account confusion attacks
# ============================================

resource "aws_s3_bucket_policy" "dr_cloudtrail" {
  provider = aws.dr
  bucket   = aws_s3_bucket.dr_cloudtrail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowReplicationWrite"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.s3_replication.arn
        }
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags",
          "s3:ObjectOwnerOverrideToBucketOwner"
        ]
        Resource  = "${aws_s3_bucket.dr_cloudtrail.arn}/*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AllowVersioningCheck"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.s3_replication.arn
        }
        Action   = "s3:GetBucketVersioning"
        Resource = aws_s3_bucket.dr_cloudtrail.arn
      }
    ]
  })

  depends_on = [
    aws_s3_bucket_public_access_block.dr_cloudtrail,
    aws_s3_bucket_versioning.dr_cloudtrail
  ]
}

resource "aws_s3_bucket_policy" "dr_config" {
  provider = aws.dr
  bucket   = aws_s3_bucket.dr_config.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowReplicationWrite"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.s3_replication.arn
        }
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags",
          "s3:ObjectOwnerOverrideToBucketOwner"
        ]
        Resource  = "${aws_s3_bucket.dr_config.arn}/*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AllowVersioningCheck"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.s3_replication.arn
        }
        Action   = "s3:GetBucketVersioning"
        Resource = aws_s3_bucket.dr_config.arn
      }
    ]
  })

  depends_on = [
    aws_s3_bucket_public_access_block.dr_config,
    aws_s3_bucket_versioning.dr_config
  ]
}

# ============================================
# Replication Configuration on SOURCE Buckets (af-south-1)
# No provider = uses default af-south-1 provider
# These resources modify the primary region buckets created in Week 4
# ============================================

resource "aws_s3_bucket_replication_configuration" "cloudtrail_to_dr" {
  # No provider argument — uses default af-south-1 provider
  # References the primary CloudTrail bucket from Week 4
  bucket = local.cloudtrail_bucket_name
  role   = aws_iam_role.s3_replication.arn

  rule {
    id     = "cloudtrail-cape-town-to-ireland"
    status = "Enabled"

    # Filter — replicate all objects (no prefix filter)
    filter {
      prefix = ""
    }

    destination {
      bucket        = aws_s3_bucket.dr_cloudtrail.arn
      storage_class = "STANDARD_IA"

      # Encrypt destination objects with DR KMS key
      encryption_configuration {
        replica_kms_key_id = aws_kms_key.dr_s3.arn
      }

      # Ensure destination account owns replicated objects
      access_control_translation {
        owner = "Destination"
      }

      # Metrics and notifications for replication monitoring
      metrics {
        status = "Enabled"
        event_threshold {
          minutes = 15
        }
      }

      replication_time {
        status = "Enabled"
        time {
          minutes = 15
        }
      }
    }

    # Replicate delete markers for complete synchronization
    delete_marker_replication {
      status = "Enabled"
    }

    # Source encryption — objects encrypted with primary KMS key
    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }
  }

  # Source bucket must have versioning before replication config
  depends_on = [aws_s3_bucket_policy.dr_cloudtrail]
}

resource "aws_s3_bucket_replication_configuration" "config_to_dr" {
  bucket = local.config_bucket_name
  role   = aws_iam_role.s3_replication.arn

  rule {
    id     = "config-cape-town-to-ireland"
    status = "Enabled"

    filter {
      prefix = ""
    }

    destination {
      bucket        = aws_s3_bucket.dr_config.arn
      storage_class = "STANDARD_IA"

      encryption_configuration {
        replica_kms_key_id = aws_kms_key.dr_s3.arn
      }

      access_control_translation {
        owner = "Destination"
      }

      metrics {
        status = "Enabled"
        event_threshold {
          minutes = 15
        }
      }

      replication_time {
        status = "Enabled"
        time {
          minutes = 15
        }
      }
    }

    delete_marker_replication {
      status = "Enabled"
    }

    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }
  }

  depends_on = [aws_s3_bucket_policy.dr_config]
}

# ============================================
# CloudWatch Alarms — S3 Replication Health (af-south-1)
# These alarms live in the PRIMARY region where the source buckets are
# No provider = uses default af-south-1 provider
# ============================================

resource "aws_cloudwatch_metric_alarm" "cloudtrail_replication_latency" {
  alarm_name          = "ABSA-DR-CloudTrail-Replication-Latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ReplicationLatency"
  namespace           = "AWS/S3"
  period              = 300
  statistic           = "Maximum"
  threshold           = 900  # 15 minutes — matches RTC target
  alarm_description   = "CloudTrail S3 replication to DR is taking longer than 15 minutes"

  dimensions = {
    SourceBucket      = local.cloudtrail_bucket_name
    DestinationBucket = aws_s3_bucket.dr_cloudtrail.id
    RuleId            = "cloudtrail-cape-town-to-ireland"
  }

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-CloudTrail-Replication-Latency"
  })
}

resource "aws_cloudwatch_metric_alarm" "cloudtrail_replication_failed" {
  alarm_name          = "ABSA-DR-CloudTrail-Replication-Failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "OperationsDurationFailedReplication"
  namespace           = "AWS/S3"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "CloudTrail S3 objects are failing replication to DR"

  dimensions = {
    SourceBucket      = local.cloudtrail_bucket_name
    DestinationBucket = aws_s3_bucket.dr_cloudtrail.id
    RuleId            = "cloudtrail-cape-town-to-ireland"
  }

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-CloudTrail-Replication-Failed"
  })
}