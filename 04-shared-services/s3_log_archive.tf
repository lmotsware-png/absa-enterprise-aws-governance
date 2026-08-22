# ============================================
# S3 Log Archive — Centralized Log Storage
# ============================================

# S3 Bucket Policy — Require encryption for all log buckets
resource "aws_s3_bucket_policy" "require_encryption" {
  for_each = {
    cloudtrail = aws_s3_bucket.cloudtrail_logs.id
    config     = aws_s3_bucket.config_logs.id
    flow_logs  = aws_s3_bucket.flow_logs.id
  }

  bucket = each.value

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyUnencryptedPut"
        Effect = "Deny"
        Principal = "*"
        Action = "s3:PutObject"
        Resource = "arn:aws:s3:::${each.value}/*"
        Condition = {
          StringNotEquals = {
            "s3:x-amz-server-side-encryption" = "aws:kms"
          }
        }
      }
    ]
  })
}

# ============================================
# ADDITION TO Week 4: 04-shared-services/s3_log_archive.tf
# Add versioning to existing CloudTrail and Config buckets
# Required: S3 Cross-Region Replication needs versioning on source buckets
# ============================================

resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "config_logs" {
  bucket = aws_s3_bucket.config_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}