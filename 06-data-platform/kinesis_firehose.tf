# ============================================
# Kinesis Data Firehose — S3 Delivery
# ============================================

resource "aws_s3_bucket" "firehose_delivery" {
  bucket        = local.firehose_bucket_name
  force_destroy = false

  tags = merge(local.common_tags, {
    Name = "ABSA-Firehose-Delivery"
  })
}

resource "aws_s3_bucket_public_access_block" "firehose_delivery" {
  bucket = aws_s3_bucket.firehose_delivery.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# FIXED: Added bucket-level default encryption
# Firehose specifies KMS encryption per-object, but this ensures
# ANY object written to this bucket is encrypted even if the writer
# doesn't explicitly specify encryption settings
resource "aws_s3_bucket_server_side_encryption_configuration" "firehose_delivery" {
  bucket = aws_s3_bucket.firehose_delivery.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = local.kms_s3_arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_versioning" "firehose_delivery" {
  bucket = aws_s3_bucket.firehose_delivery.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_kinesis_firehose_delivery_stream" "transactions_to_s3" {
  name        = "absa-transactions-to-s3"
  destination = "extended_s3"

  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.transactions.arn
    role_arn           = aws_iam_role.firehose.arn
  }

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose.arn
    bucket_arn = aws_s3_bucket.firehose_delivery.arn
    prefix     = "transactions/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/"

    buffering_size     = 64
    buffering_interval = 60

    compression_format = "GZIP"

    kms_key_arn = local.kms_s3_arn

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose.name
      log_stream_name = "firehose-delivery"
    }
  }

  tags = merge(local.common_tags, {
    Name = "ABSA-Transactions-To-S3"
  })
}

resource "aws_cloudwatch_log_group" "firehose" {
  name              = "/aws/kinesisfirehose/absa-transactions-to-s3"
  retention_in_days = 30

  tags = merge(local.common_tags, {
    Name = "ABSA-Firehose-Logs"
  })
}