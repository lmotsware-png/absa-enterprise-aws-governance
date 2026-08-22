# ============================================
# OpenSearch — Log Analytics and Full-Text Search
# ============================================

resource "aws_opensearch_domain" "logs" {
  count = var.enable_opensearch ? 1 : 0

  domain_name    = var.opensearch_domain_name
  engine_version = "OpenSearch_2.11"

  cluster_config {
    instance_type            = var.opensearch_instance_type
    instance_count           = var.opensearch_instance_count
    zone_awareness_enabled   = true
    dedicated_master_enabled = true
    dedicated_master_type    = "r6g.large.search"
    dedicated_master_count   = 3
  }

  ebs_options {
    ebs_enabled = true
    volume_size = var.opensearch_volume_size
    volume_type = "gp3"
  }

  encrypt_at_rest {
    enabled    = true
    kms_key_id = local.kms_s3_arn
  }

  node_to_node_encryption {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  advanced_security_options {
    enabled                        = true
    internal_user_database_enabled = true
    master_user_options {
      master_user_name     = "absa_admin"
      master_user_password = random_password.opensearch.result
    }
  }

  vpc_options {
    subnet_ids         = local.data_subnet_ids
    security_group_ids = [local.data_security_group_id]
  }

  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action   = "es:*"
        Resource = "arn:aws:es:af-south-1:${data.aws_caller_identity.current.account_id}:domain/${var.opensearch_domain_name}/*"
        Condition = {
          IpAddress = {
            "aws:SourceIp" = local.app_subnet_cidrs
          }
        }
      }
    ]
  })

  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.opensearch.arn
    log_type                 = "INDEX_SLOW_LOGS"
  }

  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.opensearch.arn
    log_type                 = "SEARCH_SLOW_LOGS"
  }

  tags = merge(local.common_tags, {
    Name = var.opensearch_domain_name
  })
}

resource "aws_cloudwatch_log_group" "opensearch" {
  name              = "/aws/opensearch/${var.opensearch_domain_name}"
  retention_in_days = 30

  tags = merge(local.common_tags, {
    Name = "ABSA-OpenSearch-Logs"
  })
}

resource "random_password" "opensearch" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
  min_special      = 4
  min_upper        = 4
  min_lower        = 4
  min_numeric      = 4
}