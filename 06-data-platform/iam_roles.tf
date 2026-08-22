# ============================================
# Data Platform IAM Roles
# ============================================

# Kinesis Firehose Role
resource "aws_iam_role" "firehose" {
  name = "ABSA-Firehose-Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "firehose.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "ABSA-Firehose-Role"
  })
}

resource "aws_iam_role_policy" "firehose" {
  name = "ABSA-Firehose-Policy"
  role = aws_iam_role.firehose.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = "${aws_s3_bucket.firehose_delivery.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "kinesis:DescribeStream",
          "kinesis:GetShardIterator",
          "kinesis:GetRecords"
        ]
        Resource = aws_kinesis_stream.transactions.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = local.kms_s3_arn
      }
    ]
  })
}

# Glue/Athena Role
resource "aws_iam_role" "athena" {
  name = "ABSA-Athena-Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "athena.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "ABSA-Athena-Role"
  })
}

resource "aws_iam_role_policy" "athena" {
  name = "ABSA-Athena-Policy"
  role = aws_iam_role.athena.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${local.cloudtrail_bucket_name}",
          "arn:aws:s3:::${local.cloudtrail_bucket_name}/*",
          "arn:aws:s3:::${local.config_bucket_name}",
          "arn:aws:s3:::${local.config_bucket_name}/*",
          "arn:aws:s3:::${local.flow_logs_bucket_name}",
          "arn:aws:s3:::${local.flow_logs_bucket_name}/*",
          "arn:aws:s3:::${local.firehose_bucket_name}",
          "arn:aws:s3:::${local.firehose_bucket_name}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = "arn:aws:s3:::${local.athena_results_bucket}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = local.kms_s3_arn
      }
    ]
  })
}

# Redshift Role
resource "aws_iam_role" "redshift" {
  name = "ABSA-Redshift-Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "redshift.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "ABSA-Redshift-Role"
  })
}

resource "aws_iam_role_policy" "redshift" {
  name = "ABSA-Redshift-Policy"
  role = aws_iam_role.redshift.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${local.firehose_bucket_name}",
          "arn:aws:s3:::${local.firehose_bucket_name}/*"
        ]
      },
      # FIXED: Added KMS permissions so Redshift can decrypt Firehose-delivered objects
      # Without this, COPY commands fail with KMS access denied errors
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = local.kms_s3_arn
      }
    ]
  })
}