# ============================================
# Kinesis Data Streams — Real-time Transaction Streaming
# ============================================

resource "aws_kinesis_stream" "transactions" {
  name             = var.kinesis_stream_name
  shard_count      = var.kinesis_shard_count
  retention_period = var.kinesis_retention_hours

  stream_mode_details {
    stream_mode = "ON_DEMAND"
  }

  encryption_type = "KMS"
  kms_key_id      = local.kms_s3_arn

  tags = merge(local.common_tags, {
    Name = var.kinesis_stream_name
  })
}