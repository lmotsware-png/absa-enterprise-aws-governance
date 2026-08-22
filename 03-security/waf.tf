# ============================================
# AWS WAF — Web Application Firewall
# ============================================

resource "aws_wafv2_web_acl" "main" {
  count = var.enable_waf ? 1 : 0

  name        = "ABSA-Web-ACL"
  description = "WAF rules for ABSA banking application"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # Rule 1: SQL Injection Protection
  rule {
    name     = "AWS-SQL-Injection-Protection"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "ABSA-SQL-Injection"
      sampled_requests_enabled   = true
    }
  }

  # Rule 2: Cross-Site Scripting Protection
  rule {
    name     = "AWS-XSS-Protection"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "ABSA-XSS-Attacks"
      sampled_requests_enabled   = true
    }
  }

  # Rule 3: IP Reputation
  rule {
    name     = "AWS-IP-Reputation"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "ABSA-IP-Reputation"
      sampled_requests_enabled   = true
    }
  }

  # Rule 4: Rate Limiting
  rule {
    name     = "ABSA-Rate-Limit"
    priority = 4

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "ABSA-Rate-Limit"
      sampled_requests_enabled   = true
    }
  }

  # Rule 5: User-Agent Validation
  rule {
    name     = "ABSA-Require-User-Agent"
    priority = 5

    action {
      block {
        custom_response {
          response_code = 403
          custom_response_body_key = "absa-blocked-message"
        }
      }
    }

    statement {
      not_statement {
        statement {
          byte_match_statement {
            search_string = "ABSA-Mobile"
            field_to_match {
              single_header {
                name = "user-agent"
              }
            }
            text_transformation {
              priority = 0
              type     = "NONE"
            }
            positional_constraint = "CONTAINS"
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "ABSA-User-Agent-Check"
      sampled_requests_enabled   = true
    }
  }

  # Rule 6: Geo-Restriction
  rule {
    name     = "ABSA-Geo-Restrict"
    priority = 6

    action {
      block {
        custom_response {
          response_code = 403
          custom_response_body_key = "absa-geo-blocked"
        }
      }
    }

    statement {
      not_statement {
        statement {
          geo_match_statement {
            country_codes = [
              "ZA",
              "NA",
              "BW",
              "SZ",
              "LS",
              "GB",
            ]
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "ABSA-Geo-Restrict"
      sampled_requests_enabled   = true
    }
  }

  # Rule 7: Size Restriction
  rule {
    name     = "ABSA-Size-Restriction"
    priority = 7

    action {
      block {}
    }

    statement {
      size_constraint_statement {
        size                 = 8192
        comparison_operator  = "GT"
        field_to_match {
          body {}
        }
        text_transformation {
          priority = 0
          type     = "NONE"
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "ABSA-Size-Restriction"
      sampled_requests_enabled   = true
    }
  }

  # Custom Response Bodies
  custom_response_body {
    key          = "absa-blocked-message"
    content      = "Request blocked by ABSA security. If you believe this is an error, please contact support."
    content_type = "TEXT_PLAIN"
  }

  custom_response_body {
    key          = "absa-geo-blocked"
    content      = "Access denied. ABSA services are only available from approved regions."
    content_type = "TEXT_PLAIN"
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "ABSA-Web-ACL"
    sampled_requests_enabled   = true
  }

  tags = merge(local.common_tags, {
    Name = "ABSA-Web-ACL"
  })
}

# WAF Logging
resource "aws_cloudwatch_log_group" "waf" {
  count = var.enable_waf ? 1 : 0

  name              = "aws-waf-logs-absa"
  retention_in_days = 90

  tags = merge(local.common_tags, {
    Name = "ABSA-WAF-Logs"
  })
}

resource "aws_wafv2_web_acl_logging_configuration" "main" {
  count = var.enable_waf ? 1 : 0

  log_destination_configs = [aws_cloudwatch_log_group.waf[0].arn]
  resource_arn            = aws_wafv2_web_acl.main[0].arn
}