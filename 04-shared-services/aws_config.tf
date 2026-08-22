# ============================================
# AWS Config — Resource Compliance Tracking
# ============================================

# S3 Bucket for Config Logs
resource "aws_s3_bucket" "config_logs" {
  bucket        = local.config_bucket
  force_destroy = false

  tags = merge(local.common_tags, {
    Name = "ABSA-Config-Logs"
  })
}

resource "aws_s3_bucket_public_access_block" "config_logs" {
  bucket = aws_s3_bucket.config_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "config_logs" {
  bucket = aws_s3_bucket.config_logs.id

  rule {
    id     = "retention"
    status = "Enabled"

    expiration {
      days = var.log_retention_days
    }
  }
}

# AWS Config Recorder
resource "aws_config_configuration_recorder" "main" {
  name     = "ABSA-Config-Recorder"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

# AWS Config Delivery Channel
resource "aws_config_delivery_channel" "main" {
  name           = "ABSA-Config-Delivery-Channel"
  s3_bucket_name = aws_s3_bucket.config_logs.id

  sns_topic_arn = aws_sns_topic.config_alerts.arn

  snapshot_delivery_properties {
    delivery_frequency = "TwentyFour_Hours"
  }

  depends_on = [aws_config_configuration_recorder.main]
}

# Start Config Recorder
resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.main]
}

# Config Rules — Compliance checks
resource "aws_config_config_rule" "encrypted_volumes" {
  name        = "ABSA-Encrypted-EBS-Volumes"
  description = "Checks that all EBS volumes are encrypted"

  source {
    owner             = "AWS"
    source_identifier = "ENCRYPTED_VOLUMES"
  }

  depends_on = [aws_config_configuration_recorder.main]
}

resource "aws_config_config_rule" "rds_encryption" {
  name        = "ABSA-RDS-Encryption"
  description = "Checks that RDS instances have encryption enabled"

  source {
    owner             = "AWS"
    source_identifier = "RDS_STORAGE_ENCRYPTED"
  }

  depends_on = [aws_config_configuration_recorder.main]
}

resource "aws_config_config_rule" "s3_public_read" {
  name        = "ABSA-S3-Public-Read"
  description = "Checks that S3 buckets don't allow public read access"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }

  depends_on = [aws_config_configuration_recorder.main]
}

resource "aws_config_config_rule" "restricted_ssh" {
  name        = "ABSA-Restricted-SSH"
  description = "Checks that security groups don't allow unrestricted SSH"

  source {
    owner             = "AWS"
    source_identifier = "INCOMING_SSH_DISABLED"
  }

  depends_on = [aws_config_configuration_recorder.main]
}

# SNS Topic for Config alerts
resource "aws_sns_topic" "config_alerts" {
  name = "ABSA-Config-Alerts"

  tags = merge(local.common_tags, {
    Name = "ABSA-Config-Alerts"
  })
}

# IAM Role for AWS Config
resource "aws_iam_role" "config" {
  name = "ABSA-Config-Service-Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "ABSA-Config-Service-Role"
  })
}

resource "aws_iam_role_policy_attachment" "config" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}