# ============================================
# Route 53 — Automated DNS Failover
# ============================================
#
# Architecture:
#
#   NORMAL OPERATION:
#   Sipho → banking.absa.co.za
#         → Route 53 PRIMARY record (health check: HEALTHY)
#         → Primary CloudFront (af-south-1)
#         → Primary API Gateway → Primary EKS → Primary RDS
#
#   DR FAILOVER:
#   Sipho → banking.absa.co.za
#         → Route 53 PRIMARY record (health check: UNHEALTHY)
#         → Route 53 SECONDARY record (automatic switch)
#         → DR CloudFront (global, origin: eu-west-1 NLB)
#         → DR EKS → DR Aurora replica (promoted to writer)
#
#   DNS propagation time: var.failover_ttl = 60 seconds
#   Human intervention required: NONE (fully automatic)
#
# Provider requirements:
#   aws          — af-south-1 (primary, default)
#   aws.dr       — eu-west-1 (Ireland DR)
#   aws.us_east_1 — us-east-1 (CloudFront ACM + Route53 alarms)
# ============================================

# ============================================
# SECTION 1 — Existing Hosted Zone
# ============================================
# FIXED: was resource (creates duplicate zone), now data source.
# The absa.co.za zone already exists — used by Week 5's
# alb.tf and cloudfront.tf for ACM validation and DNS records.
# Creating a second zone causes split-horizon DNS and
# unpredictable resolution for a percentage of customers.
# ============================================

data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}

# ============================================
# SECTION 2 — DR CloudFront ACM Certificate
# ============================================
# AWS hard requirement: CloudFront certificates MUST be in
# us-east-1 regardless of where the origin lives.
# The DR CloudFront serves banking.absa.co.za — same domain
# as the primary CloudFront — making failover transparent
# to customers. A separate certificate is required because
# the primary certificate (Week 5) is owned by Week 5's stack.
# ============================================

resource "aws_acm_certificate" "dr_cloudfront" {
  provider = aws.us_east_1

  domain_name       = "banking.${var.domain_name}"
  validation_method = "DNS"

  subject_alternative_names = [
    "*.banking.${var.domain_name}"
  ]

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-CloudFront-Certificate"
  })
}

# DNS validation records — prove ABSA owns banking.absa.co.za
# by adding ACM-generated CNAME records to the existing zone
resource "aws_route53_record" "dr_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.dr_cloudfront.domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = data.aws_route53_zone.main.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60
}

# Wait resource — Terraform blocks until certificate status
# transitions from PENDING_VALIDATION to ISSUED before
# allowing the CloudFront distribution to be created.
# The distribution references .certificate_arn which is only
# populated after this validation completes.
resource "aws_acm_certificate_validation" "dr_cloudfront" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.dr_cloudfront.arn
  validation_record_fqdns = [for record in aws_route53_record.dr_cert_validation : record.fqdn]
}

# ============================================
# SECTION 3 — DR CloudFront Logs Bucket
# ============================================
# CloudFront requires object_ownership = "BucketOwnerPreferred"
# on the log destination bucket. Without this, CloudFront's
# log delivery using the bucket-owner-full-control ACL is
# rejected — the distribution silently stops logging.
# ============================================

resource "aws_s3_bucket" "dr_cloudfront_logs" {
  provider      = aws.dr
  bucket        = "absa-dr-cloudfront-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = false

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-CloudFront-Logs"
  })
}

resource "aws_s3_bucket_public_access_block" "dr_cloudfront_logs" {
  provider = aws.dr
  bucket   = aws_s3_bucket.dr_cloudfront_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Required for CloudFront log delivery — without BucketOwnerPreferred
# CloudFront cannot write access logs to this bucket
resource "aws_s3_bucket_ownership_controls" "dr_cloudfront_logs" {
  provider = aws.dr
  bucket   = aws_s3_bucket.dr_cloudfront_logs.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# ============================================
# SECTION 4 — DR CloudFront Distribution
# ============================================
# CloudFront is a globally distributed service — no regional
# provider is needed. The distribution has no home region;
# the API is called through the global CloudFront endpoint.
# The origin happens to be in eu-west-1 but the distribution
# itself is globally deployed to all CloudFront edge locations.
#
# price_class = PriceClass_All — includes Johannesburg edge.
# PriceClass_100 excludes Africa; Sipho must reach a nearby
# edge during DR mode, not route through Europe.
# ============================================

resource "aws_cloudfront_distribution" "dr" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "ABSA DR Banking — eu-west-1 failover distribution"
  default_root_object = ""
  price_class         = "PriceClass_All"

  # Same alias as primary CloudFront — makes failover
  # completely transparent to customers. Route 53 determines
  # which distribution serves requests at any given moment.
  aliases = ["banking.${var.domain_name}"]

  # Origin: DR NLB in eu-west-1 (from eks_warm_standby.tf)
  # Traffic path during DR: CloudFront → NLB → ALB → EKS pod
  origin {
    domain_name = aws_lb.dr_nlb.dns_name
    origin_id   = "ABSA-DR-NLB"
    origin_path = "/prod"

    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_protocol_policy   = "https-only"
      origin_ssl_protocols     = ["TLSv1.2"]
      origin_read_timeout      = 30
      origin_keepalive_timeout = 5
    }

    # Verification header — DR API Gateway resource policy
    # enforces this header as the only authorized traffic source.
    # Prevents direct NLB bypass during DR mode.
    custom_header {
      name  = "X-Origin-Verify"
      value = "absa-cloudfront-to-dr-api-gateway"
    }
  }

  # All methods forwarded — banking API requires POST (payments),
  # PUT (account updates), DELETE (session termination)
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "ABSA-DR-NLB"

    forwarded_values {
      query_string = true

      # Authorization header must survive CloudFront hop —
      # IRSA authentication at the DR pod requires it intact.
      # X-Origin-Verify forwarded so the DR API Gateway
      # can validate the CloudFront source.
      headers = [
        "Authorization",
        "Content-Type",
        "User-Agent",
        "X-Forwarded-For",
        "X-Origin-Verify"
      ]

      # AWSALB stickiness cookie must flow through for
      # session affinity in the DR EKS cluster
      cookies {
        forward = "all"
      }
    }

    # All TTLs = 0 — banking API responses are never cached.
    # Every request reaches the DR backend for current data.
    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
    compress               = true
  }

  # Geo-restriction managed by WAF (web_acl_id below),
  # not by CloudFront's built-in restriction — keeps all
  # security rules in one place for consistent enforcement
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Certificate must be ISSUED before CloudFront accepts it —
  # reference the validation resource, not the certificate directly
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.dr_cloudfront.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  # Same WAF as primary site (Week 3, scope = CLOUDFRONT).
  # All 7 rules active during DR: SQL injection, XSS,
  # IP reputation, rate limiting, User-Agent, geo-restriction,
  # size limits — identical protection in DR mode.
  web_acl_id = local.waf_acl_arn

  logging_config {
    include_cookies = false
    bucket          = aws_s3_bucket.dr_cloudfront_logs.bucket_domain_name
    prefix          = "cloudfront-dr-logs/"
  }

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-CloudFront-Distribution"
  })

  # Explicit dependency — ensures certificate is fully issued
  # before distribution is created. Belt-and-braces alongside
  # the implicit dependency through viewer_certificate ARN.
  depends_on = [
    aws_acm_certificate_validation.dr_cloudfront,
    aws_s3_bucket_ownership_controls.dr_cloudfront_logs
  ]
}

# ============================================
# SECTION 5 — Route 53 Health Checks
# ============================================
# Route 53 health checkers are globally distributed AWS
# infrastructure — external to the VPC, testing endpoints
# exactly as Sipho's phone would experience them.
#
# PRIMARY health check: monitors banking.absa.co.za
#   — the customer-facing endpoint
#   — 3 consecutive failures × 30s interval = 90s to trigger
#
# DR health check: monitors the DR CloudFront domain directly
#   — NOT banking.absa.co.za (would be circular during failover)
#   — validates DR site is healthy BEFORE it's ever needed
#   — uses CloudFront's auto-generated domain to avoid
#     the circular dependency of checking the alias during failover
# ============================================

resource "aws_route53_health_check" "primary" {
  fqdn              = "banking.${var.domain_name}"
  port              = 443
  type              = "HTTPS"
  resource_path     = "/health"
  failure_threshold = 3
  request_interval  = 30

  tags = merge(local.common_tags, {
    Name = "ABSA-Primary-Health-Check"
  })
}

resource "aws_route53_health_check" "dr" {
  # FIXED: was "dr.banking.absa.co.za" (non-existent endpoint).
  # Must monitor the DR CloudFront's own domain — not the alias.
  # Using the alias creates a circular dependency during failover:
  # when primary fails, banking.absa.co.za resolves to DR, so
  # checking banking.absa.co.za would check the same thing
  # Route 53 is trying to route away from.
  fqdn              = aws_cloudfront_distribution.dr.domain_name
  port              = 443
  type              = "HTTPS"
  resource_path     = "/health"
  failure_threshold = 3
  request_interval  = 30

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-Health-Check"
  })
}

# ============================================
# SECTION 6 — Route 53 Failover DNS Records
# ============================================
# Two A records with the same name (banking.absa.co.za).
# Route 53 failover routing serves the PRIMARY record when
# its health check is healthy. When the PRIMARY health check
# fails (3 consecutive failures), Route 53 automatically
# serves the SECONDARY record — no human intervention needed.
#
# set_identifier distinguishes the two same-name records.
# failover_routing_policy declares which is PRIMARY/SECONDARY.
#
# FIXED primary record: was aws_route53_zone.main (resource,
# creates duplicate zone). Now data.aws_route53_zone.main.
#
# FIXED DR record: was alias name = "dr.banking.absa.co.za"
# (non-existent AWS resource DNS name). Now points at
# aws_cloudfront_distribution.dr.domain_name — a real
# CloudFront distribution created in this file.
# ============================================

resource "aws_route53_record" "banking_primary" {
  zone_id        = data.aws_route53_zone.main.zone_id
  name           = "banking"
  type           = "A"
  set_identifier = "primary-af-south-1"

  alias {
    # Primary CloudFront domain from Week 5 outputs
    # e.g. dXXXXXXXXXXXX.cloudfront.net
    name    = local.primary_cloudfront_domain
    zone_id = "Z2FDTNDATAQYW2" # Fixed zone ID for all CloudFront distributions
    evaluate_target_health = true
  }

  health_check_id = aws_route53_health_check.primary.id

  failover_routing_policy {
    type = "PRIMARY"
  }
}

resource "aws_route53_record" "banking_dr" {
  zone_id        = data.aws_route53_zone.main.zone_id
  name           = "banking"
  type           = "A"
  set_identifier = "secondary-eu-west-1"

  alias {
    # DR CloudFront distribution created in this file.
    # During normal operation this record is never served.
    # During DR failover Route 53 automatically switches
    # all banking.absa.co.za resolutions to this target.
    name    = aws_cloudfront_distribution.dr.domain_name
    zone_id = "Z2FDTNDATAQYW2" # Fixed zone ID for all CloudFront distributions
    evaluate_target_health = true
  }

  health_check_id = aws_route53_health_check.dr.id

  failover_routing_policy {
    type = "SECONDARY"
  }
}

# ============================================
# SECTION 7 — CloudWatch Alarms — Health Check Monitoring
# ============================================
# CRITICAL: Route 53 health check metrics exist ONLY in
# the AWS/Route53 namespace which exists ONLY in us-east-1.
# These alarms MUST use provider = aws.us_east_1.
# Creating them in any other region results in:
# "The namespace AWS/Route53 does not exist in this region."
#
# SNS topic also in us-east-1 — CloudWatch alarms publish
# to SNS topics in the same region.
# ============================================

resource "aws_sns_topic" "route53_alerts" {
  provider = aws.us_east_1
  name     = "ABSA-Route53-Failover-Alerts"

  tags = merge(local.common_tags, {
    Name = "ABSA-Route53-Failover-Alerts"
  })
}

# Alarm: Primary health check failed
# Fires when banking.absa.co.za stops responding to health checks.
# HealthCheckStatus: 1 = healthy, 0 = unhealthy.
# LessThanThreshold + threshold=1 means: alarm when status = 0.
resource "aws_cloudwatch_metric_alarm" "primary_health_failed" {
  provider = aws.us_east_1

  alarm_name          = "ABSA-DR-Primary-Health-Check-Failed"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1

  # Missing data = the health check infrastructure itself
  # has an issue — treat as unhealthy, not as OK
  treat_missing_data = "breaching"

  alarm_description = "Primary ABSA banking health check failing — DR failover may be active or imminent"

  dimensions = {
    HealthCheckId = aws_route53_health_check.primary.id
  }

  # Alert on failure AND recovery — operations team needs
  # to know when failover starts and when primary recovers
  alarm_actions = [aws_sns_topic.route53_alerts.arn]
  ok_actions    = [aws_sns_topic.route53_alerts.arn]

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-Primary-Health-Alarm"
  })
}

# Alarm: DR health check failed
# Fires when the DR site has an issue while NOT serving traffic.
# 2 evaluation periods — DR may have brief planned maintenance;
# 2 minutes of consecutive failure signals a genuine problem.
# No ok_actions — DR recovery confirmed manually by the team.
resource "aws_cloudwatch_metric_alarm" "dr_health_failed" {
  provider = aws.us_east_1

  alarm_name          = "ABSA-DR-DR-Health-Check-Failed"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1
  treat_missing_data  = "breaching"

  alarm_description = "DR ABSA banking health check failing — DR site has an issue while not serving primary traffic"

  dimensions = {
    HealthCheckId = aws_route53_health_check.dr.id
  }

  alarm_actions = [aws_sns_topic.route53_alerts.arn]

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-DR-Health-Alarm"
  })
}