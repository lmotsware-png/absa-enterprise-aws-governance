# ============================================
# VPC Flow Logs — Network Traffic Analysis
# ============================================

# S3 Bucket for Flow Logs
resource "aws_s3_bucket" "flow_logs" {
  bucket        = local.vpc_flow_logs_bucket
  force_destroy = false

  tags = merge(local.common_tags, {
    Name = "ABSA-VPC-Flow-Logs"
  })
}

resource "aws_s3_bucket_public_access_block" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id

  rule {
    id     = "transition-to-glacier"
    status = "Enabled"

    transition {
      days          =  var.flow_logs_transition_days
      storage_class = "GLACIER"
    }

    expiration {
      days =  var.flow_logs_expiration_days
    }
  }
}

# VPC Flow Logs — Production VPC
resource "aws_flow_log" "production" {
  count = var.enable_vpc_flow_logs ? 1 : 0

  log_destination      = aws_s3_bucket.flow_logs.arn
  log_destination_type = "s3"
  traffic_type         = "ALL"
  vpc_id               = local.all_vpc_ids.production

  log_format = "${version} ${account-id} ${interface-id} ${srcaddr} ${dstaddr} ${srcport} ${dstport} ${protocol} ${packets} ${bytes} ${start} ${end} ${action} ${log-status}"

  tags = merge(local.common_tags, {
    Name = "ABSA-Production-VPC-Flow-Logs"
  })
}

# VPC Flow Logs — Finance VPC (PCI-DSS requirement)
resource "aws_flow_log" "finance" {
  count = var.enable_vpc_flow_logs ? 1 : 0

  log_destination      = aws_s3_bucket.flow_logs.arn
  log_destination_type = "s3"
  traffic_type         = "ALL"
  vpc_id               = local.all_vpc_ids.finance

  log_format = "${version} ${account-id} ${interface-id} ${srcaddr} ${dstaddr} ${srcport} ${dstport} ${protocol} ${packets} ${bytes} ${start} ${end} ${action} ${log-status}"

  tags = merge(local.common_tags, {
    Name = "ABSA-Finance-VPC-Flow-Logs"
  })
}