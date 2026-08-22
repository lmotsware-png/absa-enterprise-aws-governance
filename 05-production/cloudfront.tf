# ============================================
# CloudFront — Global CDN with WAF Protection
# ============================================

resource "aws_cloudfront_distribution" "main" {
  count = var.enable_cloudfront ? 1 : 0

  # Origin — API Gateway (regional endpoint in af-south-1 — Cape Town)
  origin {
    domain_name = "${aws_api_gateway_rest_api.main.id}.execute-api.${var.primary_region}.amazonaws.com"
    origin_id   = "ABSA-API-Gateway"
    origin_path = "/${var.api_gateway_stage}"

    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_protocol_policy   = "https-only"
      origin_ssl_protocols     = ["TLSv1.2"]
      origin_read_timeout      = 30
      origin_keepalive_timeout = 5
    }

    # Custom header — labels traffic as coming through CloudFront
    # Value is generated per deployment from random_password below
    # Actual ENFORCEMENT is in api_gateway.tf via aws_api_gateway_rest_api_policy
    custom_header {
      name  = "X-Origin-Verify"
      value = random_password.cloudfront_verify.result
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "ABSA Banking Application — Production CDN"
  default_root_object = ""

  aliases = [var.cloudfront_domain_name]

  # Default cache behavior — API requests (NO caching for banking transactions)
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "ABSA-API-Gateway"

    forwarded_values {
      query_string = true
      headers      = ["Authorization", "Content-Type", "User-Agent", "X-Forwarded-For"]

      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
    compress               = true
  }

  # Ordered cache behavior — Static assets (cached for performance)
  ordered_cache_behavior {
    path_pattern     = "/static/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "ABSA-API-Gateway"

    forwarded_values {
      query_string = false
      headers      = ["Origin"]

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 604800
    compress               = true
  }

  # Geo-restriction — deliberately NONE at CloudFront layer
  # Geo-blocking is handled by WAF Rule 6 instead
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # SSL Certificate — references the VALIDATED certificate
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.main.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  # WAF — Attach the Web ACL from Week 3
  web_acl_id = local.waf_acl_arn

  # PriceClass_All — includes African edge locations for SA customers
  price_class = "PriceClass_All"

  logging_config {
    include_cookies = false
    bucket          = aws_s3_bucket.cloudfront_logs[0].bucket
    prefix          = "cloudfront-logs/"
  }

  tags = merge(local.common_tags, {
    Name = "ABSA-CloudFront-Distribution"
  })
}

# ============================================
# CloudFront Origin Verification — Three Resources
# ============================================
# 1. random_password — generates the 32-character verification value
# 2. aws_secretsmanager_secret — creates the encrypted container
# 3. aws_secretsmanager_secret_version — stores the value for auditing
#
# The custom_header above uses this value to LABEL legitimate traffic.
# The API Gateway resource policy in api_gateway.tf uses aws:SourceArn
# to ENFORCE that only this CloudFront distribution can invoke the API.
# Together they close the gap completely.
# ============================================

resource "random_password" "cloudfront_verify" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
  min_special      = 4
  min_upper        = 4
  min_lower        = 4
  min_numeric      = 4
}

resource "aws_secretsmanager_secret" "cloudfront_verify" {
  name                    = "absa/cloudfront/origin-verify"
  description             = "X-Origin-Verify header value — labels traffic as originating from CloudFront"
  kms_key_id              = local.kms_secrets_arn
  recovery_window_in_days = 7

  tags = merge(local.common_tags, {
    Name = "ABSA-CloudFront-Origin-Verify"
  })
}

resource "aws_secretsmanager_secret_version" "cloudfront_verify" {
  secret_id     = aws_secretsmanager_secret.cloudfront_verify.id
  secret_string = random_password.cloudfront_verify.result
}

# ============================================
# S3 Bucket for CloudFront Access Logs
# ============================================

resource "aws_s3_bucket" "cloudfront_logs" {
  count = var.enable_cloudfront ? 1 : 0

  bucket        = "absa-cloudfront-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = false

  tags = merge(local.common_tags, {
    Name = "ABSA-CloudFront-Logs"
  })
}

resource "aws_s3_bucket_public_access_block" "cloudfront_logs" {
  count = var.enable_cloudfront ? 1 : 0

  bucket = aws_s3_bucket.cloudfront_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket Policy — Allow CloudFront to write logs
# Uses service principal — works in any region
# Condition restricts to THIS specific distribution only
resource "aws_s3_bucket_policy" "cloudfront_logs" {
  count = var.enable_cloudfront ? 1 : 0

  bucket = aws_s3_bucket.cloudfront_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudfront_logs[0].arn}/cloudfront-logs/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.main[0].arn
          }
        }
      }
    ]
  })
}

# ============================================
# Route 53 — DNS record for banking.absa.co.za
# Assumes a Route 53 public hosted zone for "absa.co.za" already exists
# ============================================

data "aws_route53_zone" "main" {
  name         = "absa.co.za"
  private_zone = false
}

resource "aws_route53_record" "banking" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "banking.absa.co.za"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main[0].domain_name
    zone_id                = "Z2FDTNDATAQYW2"
    evaluate_target_health = false
  }
}

data "aws_caller_identity" "current" {}