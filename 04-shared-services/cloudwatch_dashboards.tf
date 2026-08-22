# ============================================
# CloudWatch Dashboards — Central Monitoring
# ============================================

# CloudWatch Dashboard — ABSA Production Overview
resource "aws_cloudwatch_dashboard" "production" {
  dashboard_name = "ABSA-Production-Overview"
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/EKS", "cluster_failure", { stat = "Sum" }],
            ["AWS/RDS", "DatabaseConnections", { stat = "Average" }],
            ["AWS/ElastiCache", "CPUUtilization", { stat = "Average" }]
          ]
          region = var.primary_region
          title  = "Core Service Health"
          period = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 6
        height = 6
        properties = {
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/ApiGateway", "Count", { stat = "Sum" }],
            ["AWS/ApiGateway", "4xx", { stat = "Sum" }],
            ["AWS/ApiGateway", "5xx", { stat = "Sum" }]
          ]
          region = var.primary_region
          title  = "API Gateway Traffic"
          period = 60
        }
      },
      {
        type   = "metric"
        x      = 6
        y      = 6
        width  = 6
        height = 6
        properties = {
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", { stat = "Sum" }],
            ["AWS/ApplicationELB", "TargetResponseTime", { stat = "Average" }]
          ]
          region = var.primary_region
          title  = "ALB Performance"
          period = 60
        }
      }
    ]
  })
}

# CloudWatch Dashboard — Security Overview
resource "aws_cloudwatch_dashboard" "security" {
  dashboard_name = "ABSA-Security-Overview"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/GuardDuty", "Findings", { stat = "Sum" }],
            ["AWS/WAF", "BlockedRequests", { stat = "Sum" }],
            ["AWS/CloudTrail", "ApiCalls", { stat = "Sum" }]
          ]
          region = var.primary_region
          title  = "Security Events"
          period = 300
        }
      }
    ]
  })
}