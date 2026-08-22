# ============================================
# Amazon GuardDuty — Intelligent Threat Detection
# ============================================

# GuardDuty Detector — The main threat detection engine
resource "aws_guardduty_detector" "main" {
  count = var.enable_guardduty ? 1 : 0

  enable                       = true
  finding_publishing_frequency = var.guardduty_finding_publishing_frequency

  tags = merge(local.common_tags, {
    Name = "ABSA-GuardDuty-Detector"
  })
}

# GuardDuty Organization Admin — Centralize findings from all accounts
resource "aws_guardduty_organization_admin_account" "main" {
  count = var.enable_guardduty ? 1 : 0

  admin_account_id = data.aws_caller_identity.current.account_id

  depends_on = [aws_guardduty_detector.main]
}

# GuardDuty Organization Configuration — Auto-enable for new accounts
resource "aws_guardduty_organization_configuration" "main" {
  count = var.enable_guardduty ? 1 : 0

  auto_enable_organization_members = "ALL"
  detector_id                      = aws_guardduty_detector.main[0].id

  depends_on = [aws_guardduty_organization_admin_account.main]
}

# # EventBridge Rule (Terraform resource name: aws_cloudwatch_event_rule)
# Forwards GuardDuty findings to Security Hub and SNS
resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  count = var.enable_guardduty ? 1 : 0

  name        = "ABSA-GuardDuty-Findings-Rule"
  description = "Captures all GuardDuty findings and forwards them"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail_type = ["GuardDuty Finding"]
  })

  tags = merge(local.common_tags, {
    Name = "ABSA-GuardDuty-Findings-Rule"
  })
}

# SNS Topic for GuardDuty Alerts
resource "aws_sns_topic" "guardduty_alerts" {
  count = var.enable_guardduty ? 1 : 0

  name = "ABSA-GuardDuty-Alerts"

  tags = merge(local.common_tags, {
    Name = "ABSA-GuardDuty-Alerts"
  })
}

# CloudWatch Event Target — Send findings to SNS
resource "aws_cloudwatch_event_target" "guardduty_to_sns" {
  count = var.enable_guardduty ? 1 : 0

  rule      = aws_cloudwatch_event_rule.guardduty_findings[0].name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.guardduty_alerts[0].arn
}

# SNS Topic Policy — Allow EventBridge to publish
resource "aws_sns_topic_policy" "guardduty_alerts" {
  count = var.enable_guardduty ? 1 : 0

  arn = aws_sns_topic.guardduty_alerts[0].arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.guardduty_alerts[0].arn
      }
    ]
  })
}