# ============================================
# Kinesis Data Analytics V2 — Real-Time Stream Processing
# ============================================

resource "aws_kinesisanalyticsv2_application" "fraud_detection" {
  count = var.enable_kinesis_analytics ? 1 : 0

  name                   = "ABSA-Real-Time-Fraud-Analytics"
  runtime_environment    = "FLINK-1_18"
  service_execution_role = aws_iam_role.kinesis_analytics.arn
  start_application      = true

  application_configuration {
    application_code_configuration {
      code_content_type = "ZIPFILE"
      code_content {
        s3_content_location {
          bucket_arn = aws_s3_bucket.firehose_delivery.arn
          file_key   = "analytics/fraud-detection-app.zip"
        }
      }
    }

    environment_properties {
      property_group {
        property_group_id = "InputStream"
        property_map = {
          "INPUT_STREAM_ARN"  = aws_kinesis_stream.transactions.arn
          "OUTPUT_STREAM_ARN" = aws_kinesis_firehose_delivery_stream.transactions_to_s3.arn
          "REGION"            = var.primary_region
        }
      }
    }

    flink_application_configuration {
      checkpoint_configuration {
        configuration_type = "DEFAULT"
      }

      monitoring_configuration {
        configuration_type = "DEFAULT"
        log_level          = "INFO"
      }

      parallelism_configuration {
        configuration_type   = "CUSTOM"
        parallelism          = 2
        parallelism_per_kpu  = 1
        auto_scaling_enabled = true
      }
    }
  }

  cloudwatch_logging_options {
    log_stream_arn = "${aws_cloudwatch_log_group.kinesis_analytics.arn}:*"
  }

  tags = merge(local.common_tags, {
    Name = "ABSA-Real-Time-Fraud-Analytics"
  })
}

# CloudWatch Log Group for Kinesis Analytics
resource "aws_cloudwatch_log_group" "kinesis_analytics" {
  name              = "/aws/kinesis-analytics/ABSA-Real-Time-Fraud-Analytics"
  retention_in_days = 30

  tags = merge(local.common_tags, {
    Name = "ABSA-Kinesis-Analytics-Logs"
  })
}

# IAM Role for Kinesis Analytics
resource "aws_iam_role" "kinesis_analytics" {
  name = "ABSA-Kinesis-Analytics-Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "kinesisanalytics.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "ABSA-Kinesis-Analytics-Role"
  })
}

resource "aws_iam_role_policy" "kinesis_analytics" {
  name = "ABSA-Kinesis-Analytics-Policy"
  role = aws_iam_role.kinesis_analytics.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:DescribeStream",
          "kinesis:GetShardIterator",
          "kinesis:GetRecords",
          "kinesis:DescribeStreamSummary",
          "kinesis:SubscribeToShard",
          "kinesis:ListShards"
        ]
        Resource = aws_kinesis_stream.transactions.arn
      },
      {
        Effect = "Allow"
        Action = [
          "firehose:PutRecord",
          "firehose:PutRecordBatch",
          "firehose:DescribeDeliveryStream"
        ]
        Resource = aws_kinesis_firehose_delivery_stream.transactions_to_s3.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = "${aws_s3_bucket.firehose_delivery.arn}/analytics/*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:PutLogEvents",
          "logs:CreateLogStream",
          "logs:CreateLogGroup",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "${aws_cloudwatch_log_group.kinesis_analytics.arn}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}