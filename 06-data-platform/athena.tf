# ============================================
# Athena — Serverless SQL Queries on S3
# ============================================

# S3 Bucket for Athena Query Results
resource "aws_s3_bucket" "athena_results" {
  bucket        = local.athena_results_bucket
  force_destroy = false

  tags = merge(local.common_tags, {
    Name = "ABSA-Athena-Results"
  })
}

# Public access block — query results contain sensitive customer data
resource "aws_s3_bucket_public_access_block" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ============================================
# Glue Data Catalog — Athena's Index System
# ============================================
# Before Athena can query S3 files, it needs to know:
#   - Where are the files? (S3 location)
#   - What format are they in? (JSON, Parquet, CSV)
#   - What columns do they have? (schema)
#   - How are they partitioned? (year/month/day/hour)
#
# The Glue Data Catalog stores this metadata.
# It's the card catalog — Athena reads it to understand
# your data before reading the actual S3 files.

# Glue Catalog Database — Logical container for tables
resource "aws_glue_catalog_database" "analytics" {
  name        = "absa_logs"
  description = "ABSA analytics database — transaction events, CloudTrail logs, Config snapshots, VPC flow logs"
}

# Glue Catalog Table — Virtual table definition for transaction events
# No data moves — this just tells Athena how to interpret the S3 files
resource "aws_glue_catalog_table" "transactions" {
  name          = "transactions"
  database_name = aws_glue_catalog_database.analytics.name
  description   = "Transaction events delivered by Kinesis Firehose — one JSON object per line"

  # Where the data lives in S3
  storage_descriptor {
    location      = "s3://${local.firehose_bucket_name}/transactions/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    # JSON SerDe — parses each line as a JSON object
    ser_de_info {
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
      parameters = {
        "serialization.format" = "1"
        "ignore.malformed.json" = "true"   # Skip broken records instead of failing the query
      }
    }

    # Column definitions — the schema Athena uses to interpret JSON fields
    columns {
      name = "transaction_id"
      type = "string"
    }
    columns {
      name = "user_id"  
      type = "string"
    }
    columns {
      name = "from_account"
      type = "string"
    }
    columns {
      name = "to_account"
      type = "string"
    }
    columns {
      name = "amount"
      type = "decimal(15,2)"   # Exact decimal — never float for money
    }
    columns {
      name = "currency"
      type = "string"
    }
    columns {
      name = "fraud_score"
      type = "int"
    }
    columns {
      name = "status"
      type = "string"
    }
    columns {
      name = "location"
      type = "string"
    }
    columns {
      name = "timestamp"
      type = "timestamp"
    }
  }

  # Partition keys — these match the Hive-style prefixes from Firehose
  # year=2026/month=06/day=25/hour=10/
  partition_keys {
    name = "year"
    type = "string"
  }
  partition_keys {
    name = "month"
    type = "string"
  }
  partition_keys {
    name = "day"
    type = "string"
  }
  partition_keys {
    name = "hour"
    type = "string"
  }

  # When false: Athena must be told about new partitions manually
  # When true: expensive operation — only for small datasets
  # For ABSA: use partition projection or MSCK REPAIR TABLE periodically
  parameters = {
    "skip.header.line.count" = "0"
    "projection.enabled"     = "true"
  }
}

# ============================================
# Athena Workgroup — Query Management and Cost Control
# ============================================

resource "aws_athena_workgroup" "main" {
  name        = "ABSA-Analytics-Workgroup"
  description = "ABSA analytics workgroup — enforces encryption, output location, and cost limits"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/query-results/"

      encryption_configuration {
        encryption_option = "SSE_KMS"
        kms_key_arn       = local.kms_s3_arn
      }
    }

    # FIXED: Added data scan limit per query
    # Prevents accidental full-table scans from costing thousands
    # 10GB = 10737418240 bytes
    # At $5/TB: maximum $0.05 per query
    bytes_scanned_cutoff_per_query = var.athena_bytes_scanned_limit
  }

  tags = merge(local.common_tags, {
    Name = "ABSA-Analytics-Workgroup"
  })
}

# ============================================
# Athena Named Queries — Pre-built SQL for Common Analysis
# ============================================

resource "aws_athena_named_query" "daily_transaction_count" {
  name        = "daily-transaction-count"
  workgroup   = aws_athena_workgroup.main.name
  database    = aws_glue_catalog_database.analytics.name
  description = "Count transactions by day for the last 30 days"

  query = <<-SQL
    SELECT 
      DATE(timestamp) as transaction_date,
      COUNT(*) as transaction_count,
      SUM(amount) as total_amount_zar,
      AVG(amount) as average_amount_zar
    FROM transactions
    WHERE timestamp >= CURRENT_DATE - INTERVAL '30' DAY
    GROUP BY DATE(timestamp)
    ORDER BY transaction_date DESC
  SQL
}

resource "aws_athena_named_query" "fraud_by_region" {
  name        = "fraud-by-region"
  workgroup   = aws_athena_workgroup.main.name
  database    = aws_glue_catalog_database.analytics.name
  description = "Analyze fraud scores by geographic location for the last 7 days"

  query = <<-SQL
    SELECT 
      location,
      COUNT(*) as transaction_count,
      AVG(fraud_score) as avg_fraud_score,
      COUNT(CASE WHEN fraud_score > 50 THEN 1 END) as high_risk_count
    FROM transactions
    WHERE timestamp >= CURRENT_DATE - INTERVAL '7' DAY
    GROUP BY location
    ORDER BY avg_fraud_score DESC
  SQL
}

resource "aws_athena_named_query" "waf_blocked_requests" {
  name        = "waf-blocked-requests"
  workgroup   = aws_athena_workgroup.main.name
  database    = aws_glue_catalog_database.analytics.name
  description = "Analyze WAF blocked requests from CloudTrail logs — last 24 hours"

  query = <<-SQL
    SELECT 
      sourceipaddress,
      useragent,
      COUNT(*) as blocked_count
    FROM cloudtrail_logs
    WHERE eventname = 'PutBucketAcl'
      AND errorcode = 'AccessDenied'
      AND timestamp >= CURRENT_DATE - INTERVAL '1' DAY
    GROUP BY sourceipaddress, useragent
    ORDER BY blocked_count DESC
    LIMIT 20
  SQL
}