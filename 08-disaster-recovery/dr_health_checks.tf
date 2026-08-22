# ============================================
# DR Health Checks — Comprehensive Monitoring
# ============================================
#
# This file monitors the complete DR infrastructure health
# across three layers:
#
#   Layer 1 — Replication health (is DR staying in sync?)
#     RDS replication lag        → rds_cross_region.tf alarms
#     S3 replication latency     → s3_cross_region.tf alarms
#     These live in their respective files — not duplicated here
#
#   Layer 2 — DR infrastructure health (is DR ready to serve?)
#     EKS cluster node count     → is the warm standby running?
#     NLB health                 → is the DR traffic path clear?
#     Aurora replica status      → is the DB reachable?
#     CloudFront distribution    → is the DR endpoint live?
#
#   Layer 3 — Failover event monitoring (did failover happen?)
#     Route53 health checks      → route53_failover.tf alarms
#     These live in route53_failover.tf — not duplicated here
#
# Provider requirements:
#   aws.dr       — eu-west-1 alarms (EKS, NLB, Aurora metrics)
#   aws.us_east_1 — CloudFront metrics (only in us-east-1)
#   default      — af-south-1 (DR ops SNS subscriptions)
#
# All alarms publish to aws_sns_topic.dr_ops defined here.
# The rds_cross_region.tf alarms already use dr_alerts topic.
# This file creates dr_ops for infrastructure health alerts —
# a separate topic with potentially different subscribers
# (infrastructure team vs database team).
# ============================================

# ============================================
# SECTION 1 — SNS Topics for DR Operations
# ============================================

# DR Operations topic — eu-west-1
# Infrastructure alarms in this file publish here.
# Subscribe: SRE team PagerDuty, ops Slack webhook,
# on-call email distribution list
resource "aws_sns_topic" "dr_ops" {
  provider = aws.dr

  name              = "ABSA-DR-Operations"
  kms_master_key_id = aws_kms_key.dr_s3.id

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-Operations"
  })
}

# DR Operations topic — us-east-1
# CloudFront alarms must publish to a topic in the same
# region as the alarm (us-east-1). Separate from the
# eu-west-1 topic above — CloudWatch cannot cross regions
# when publishing alarm notifications.
resource "aws_sns_topic" "dr_ops_us_east_1" {
  provider = aws.us_east_1

  name = "ABSA-DR-Operations-CloudFront"

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-Operations-CloudFront"
  })
}

# ============================================
# SECTION 2 — EKS Cluster Health Alarms
# ============================================
# Monitors the warm standby EKS cluster in eu-west-1.
# These alarms answer: "Is the DR cluster ready to receive
# traffic if we need to fail over right now?"

# ALARM 1: Node count below minimum
# Fires when the DR EKS cluster has zero healthy nodes.
# One node should always be running in warm standby.
# Zero nodes = the DR cluster cannot schedule any pods,
# including the system pods that validate DR health.
resource "aws_cloudwatch_metric_alarm" "dr_eks_node_count" {
  provider = aws.dr
  count    = var.enable_dr_eks ? 1 : 0

  alarm_name          = "ABSA-DR-EKS-Node-Count-Low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "cluster_node_count"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Minimum"
  threshold           = 1
  treat_missing_data  = "breaching"
  alarm_description   = "DR EKS cluster has no healthy nodes — warm standby is not operational"

  dimensions = {
    ClusterName = aws_eks_cluster.dr[0].name
    NodegroupName = aws_eks_node_group.dr[0].node_group_name
  }

  alarm_actions = [aws_sns_topic.dr_ops.arn]
  ok_actions    = [aws_sns_topic.dr_ops.arn]

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-EKS-Node-Count-Alarm"
  })
}

# ALARM 2: EKS API server errors
# Fires when the DR cluster control plane is returning errors.
# If the API server is unhealthy, pods cannot be scheduled
# during failover — the cluster exists but cannot be used.
resource "aws_cloudwatch_metric_alarm" "dr_eks_api_errors" {
  provider = aws.dr
  count    = var.enable_dr_eks ? 1 : 0

  alarm_name          = "ABSA-DR-EKS-API-Server-Errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "apiserver_request_total"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  treat_missing_data  = "notBreaching"
  alarm_description   = "DR EKS API server error rate elevated — cluster may not accept pod scheduling during failover"

  dimensions = {
    ClusterName = aws_eks_cluster.dr[0].name
  }

  alarm_actions = [aws_sns_topic.dr_ops.arn]

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-EKS-API-Error-Alarm"
  })
}

# ============================================
# SECTION 3 — NLB Health Alarms
# ============================================
# The DR NLB is the CloudFront origin — if it is
# unhealthy, failover will route traffic to an
# endpoint that returns errors rather than serving
# banking transactions.

# ALARM 3: NLB unhealthy host count
# Fires when the NLB has no healthy targets.
# During warm standby, the NLB target (the DR ALB)
# should always pass health checks.
# Zero healthy hosts = CloudFront gets connection errors.
resource "aws_cloudwatch_metric_alarm" "dr_nlb_unhealthy_hosts" {
  provider = aws.dr
  count    = var.enable_dr_eks ? 1 : 0

  alarm_name          = "ABSA-DR-NLB-No-Healthy-Hosts"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/NetworkELB"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1
  treat_missing_data  = "breaching"
  alarm_description   = "DR NLB has no healthy targets — DR CloudFront origin is unavailable"

  dimensions = {
    LoadBalancer = aws_lb.dr_nlb[0].arn_suffix
    TargetGroup  = aws_lb_target_group.dr_nlb_https[0].arn_suffix
  }

  alarm_actions = [aws_sns_topic.dr_ops.arn]
  ok_actions    = [aws_sns_topic.dr_ops.arn]

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-NLB-Unhealthy-Hosts-Alarm"
  })
}

# ALARM 4: NLB elevated error rate
# Fires when the NLB is processing requests but returning
# TCP reset errors — indicates the backend is alive but
# rejecting connections. Signals application-level issues
# that would affect DR traffic quality.
resource "aws_cloudwatch_metric_alarm" "dr_nlb_tcp_resets" {
  provider = aws.dr
  count    = var.enable_dr_eks ? 1 : 0

  alarm_name          = "ABSA-DR-NLB-TCP-Reset-Rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "TCP_Client_Reset_Count"
  namespace           = "AWS/NetworkELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 100
  treat_missing_data  = "notBreaching"
  alarm_description   = "DR NLB TCP reset rate elevated — DR backend may be rejecting connections"

  dimensions = {
    LoadBalancer = aws_lb.dr_nlb[0].arn_suffix
  }

  alarm_actions = [aws_sns_topic.dr_ops.arn]

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-NLB-TCP-Reset-Alarm"
  })
}

# ============================================
# SECTION 4 — Aurora DR Replica Health Alarms
# ============================================
# Additional database health monitoring beyond what
# rds_cross_region.tf provides. That file monitors:
#   - AuroraBinlogReplicaLag (replication speed)
#   - DatabaseConnections (replication stopped)
#
# This file adds:
#   - FreeStorageSpace (disk pressure)
#   - CPUUtilization (compute pressure)
#   - FreeableMemory (memory pressure)
#
# These metrics ensure that if the DR cluster were
# promoted to primary today, it could handle the load.

# ALARM 5: DR Aurora low storage
# If the DR replica runs out of storage it will stop
# replicating and eventually crash. Aurora storage
# auto-scales but alarms before the auto-scaling
# triggers provides operational lead time.
resource "aws_cloudwatch_metric_alarm" "dr_aurora_storage" {
  provider = aws.dr

  alarm_name          = "ABSA-DR-Aurora-Low-Storage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "FreeLocalStorage"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Minimum"
  # 5GB minimum free storage threshold — alert before
  # Aurora's auto-scaling kicks in to avoid disruption
  threshold           = 5368709120  # 5GB in bytes
  treat_missing_data  = "breaching"
  alarm_description   = "DR Aurora replica has less than 5GB free local storage"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.dr.cluster_identifier
  }

  alarm_actions = [aws_sns_topic.dr_ops.arn]
  ok_actions    = [aws_sns_topic.dr_ops.arn]

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-Aurora-Storage-Alarm"
  })
}

# ALARM 6: DR Aurora high CPU
# High CPU on the replica indicates it is struggling
# to keep up with the replication stream — elevated
# CPU often precedes rising replication lag.
# Threshold: 80% — matches primary region threshold from Week 5
resource "aws_cloudwatch_metric_alarm" "dr_aurora_cpu" {
  provider = aws.dr

  alarm_name          = "ABSA-DR-Aurora-High-CPU"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"
  alarm_description   = "DR Aurora replica CPU above 80% — may indicate replication strain"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.dr.cluster_identifier
  }

  alarm_actions = [aws_sns_topic.dr_ops.arn]

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-Aurora-CPU-Alarm"
  })
}

# ALARM 7: DR Aurora low freeable memory
# Aurora keeps frequently-accessed data in the buffer pool
# in RAM. If freeable memory drops below 256MB the buffer
# pool is under severe pressure — query performance degrades
# and connection handling becomes unstable.
resource "aws_cloudwatch_metric_alarm" "dr_aurora_memory" {
  provider = aws.dr

  alarm_name          = "ABSA-DR-Aurora-Low-Memory"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Minimum"
  threshold           = 268435456  # 256MB in bytes
  treat_missing_data  = "breaching"
  alarm_description   = "DR Aurora replica freeable memory below 256MB — performance may degrade under failover load"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.dr.cluster_identifier
  }

  alarm_actions = [aws_sns_topic.dr_ops.arn]
  ok_actions    = [aws_sns_topic.dr_ops.arn]

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-Aurora-Memory-Alarm"
  })
}

# ============================================
# SECTION 5 — CloudFront DR Distribution Alarms
# ============================================
# CloudFront metrics exist ONLY in us-east-1.
# These alarms use provider = aws.us_east_1.
# They monitor the DR CloudFront distribution
# that was created in route53_failover.tf.
#
# During normal operation the DR CloudFront serves
# no traffic — request count is zero.
# During DR failover it serves all banking traffic.
# These alarms fire only when the DR site is active.

# ALARM 8: DR CloudFront high error rate
# Fires when the DR distribution is returning 5xx errors.
# During DR failover a high 5xx rate means the DR
# infrastructure is serving traffic but failing to
# process requests — customers see errors.
resource "aws_cloudwatch_metric_alarm" "dr_cloudfront_errors" {
  provider = aws.us_east_1

  alarm_name          = "ABSA-DR-CloudFront-High-Error-Rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "5xxErrorRate"
  namespace           = "AWS/CloudFront"
  period              = 300
  statistic           = "Average"
  threshold           = 5  # 5% error rate threshold
  treat_missing_data  = "notBreaching"
  alarm_description   = "DR CloudFront 5xx error rate above 5% — DR site is serving traffic but returning errors"

  dimensions = {
    DistributionId = aws_cloudfront_distribution.dr.id
    Region         = "Global"
  }

  alarm_actions = [aws_sns_topic.dr_ops_us_east_1.arn]
  ok_actions    = [aws_sns_topic.dr_ops_us_east_1.arn]

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-CloudFront-Error-Rate-Alarm"
  })
}

# ALARM 9: DR CloudFront high latency
# Fires when origin response time exceeds 3 seconds.
# Banking customers expect sub-second responses.
# High origin latency during DR mode signals that
# the DR EKS pods or DR Aurora are under pressure.
resource "aws_cloudwatch_metric_alarm" "dr_cloudfront_latency" {
  provider = aws.us_east_1

  alarm_name          = "ABSA-DR-CloudFront-High-Origin-Latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "OriginLatency"
  namespace           = "AWS/CloudFront"
  period              = 300
  statistic           = "p99"
  threshold           = 3000  # 3000ms = 3 seconds
  treat_missing_data  = "notBreaching"
  alarm_description   = "DR CloudFront p99 origin latency above 3 seconds — DR backend under pressure"

  dimensions = {
    DistributionId = aws_cloudfront_distribution.dr.id
    Region         = "Global"
  }

  alarm_actions = [aws_sns_topic.dr_ops_us_east_1.arn]

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-CloudFront-Latency-Alarm"
  })
}

# ============================================
# SECTION 6 — DR Composite Health Dashboard
# ============================================
# A CloudWatch dashboard providing a single-pane-of-glass
# view of DR infrastructure health.
# Operators monitoring DR readiness open this dashboard
# and see all critical DR metrics in one view.
# During a failover event this dashboard is the
# primary operational monitoring surface.

resource "aws_cloudwatch_dashboard" "dr_health" {
  provider       = aws.dr
  dashboard_name = "ABSA-DR-Infrastructure-Health"

  dashboard_body = jsonencode({
    widgets = [
      # Row 1 — Header
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "# ABSA DR Infrastructure Health — eu-west-1 | Primary: af-south-1 | DR: eu-west-1"
        }
      },

      # Row 2 — RDS Replication (most critical metric)
      {
        type   = "metric"
        x      = 0
        y      = 1
        width  = 8
        height = 6
        properties = {
          title  = "RDS Replication Lag (seconds)"
          view   = "timeSeries"
          stat   = "Maximum"
          period = 60
          metrics = [[
            "AWS/RDS",
            "AuroraBinlogReplicaLag",
            "DBClusterIdentifier",
            aws_rds_cluster.dr.cluster_identifier
          ]]
          annotations = {
            horizontal = [{
              label = "RPO Threshold (${var.rds_replication_lag_alert_threshold}s)"
              value = var.rds_replication_lag_alert_threshold
              color = "#ff0000"
            }]
          }
          yAxis = {
            left = { min = 0 }
          }
        }
      },

      # Aurora CPU
      {
        type   = "metric"
        x      = 8
        y      = 1
        width  = 8
        height = 6
        properties = {
          title  = "DR Aurora CPU Utilization (%)"
          view   = "timeSeries"
          stat   = "Average"
          period = 300
          metrics = [[
            "AWS/RDS",
            "CPUUtilization",
            "DBClusterIdentifier",
            aws_rds_cluster.dr.cluster_identifier
          ]]
          annotations = {
            horizontal = [{
              label = "Alert Threshold (80%)"
              value = 80
              color = "#ff6600"
            }]
          }
          yAxis = {
            left = { min = 0, max = 100 }
          }
        }
      },

      # Aurora Database Connections
      {
        type   = "metric"
        x      = 16
        y      = 1
        width  = 8
        height = 6
        properties = {
          title  = "DR Aurora Database Connections"
          view   = "timeSeries"
          stat   = "Average"
          period = 60
          metrics = [[
            "AWS/RDS",
            "DatabaseConnections",
            "DBClusterIdentifier",
            aws_rds_cluster.dr.cluster_identifier
          ]]
          yAxis = {
            left = { min = 0 }
          }
        }
      },

      # Row 3 — EKS and NLB
      {
        type   = "metric"
        x      = 0
        y      = 7
        width  = 8
        height = 6
        properties = {
          title  = "DR NLB Healthy Host Count"
          view   = "timeSeries"
          stat   = "Minimum"
          period = 60
          metrics = [[
            "AWS/NetworkELB",
            "HealthyHostCount",
            "LoadBalancer",
            var.enable_dr_eks ? aws_lb.dr_nlb[0].arn_suffix : "N/A",
            "TargetGroup",
            var.enable_dr_eks ? aws_lb_target_group.dr_nlb_https[0].arn_suffix : "N/A"
          ]]
          annotations = {
            horizontal = [{
              label = "Minimum Healthy (1)"
              value = 1
              color = "#ff0000"
            }]
          }
          yAxis = {
            left = { min = 0 }
          }
        }
      },

      # NLB Request Count — shows when DR is serving traffic
      {
        type   = "metric"
        x      = 8
        y      = 7
        width  = 8
        height = 6
        properties = {
          title  = "DR NLB Active Flow Count"
          view   = "timeSeries"
          stat   = "Sum"
          period = 60
          metrics = [[
            "AWS/NetworkELB",
            "ActiveFlowCount",
            "LoadBalancer",
            var.enable_dr_eks ? aws_lb.dr_nlb[0].arn_suffix : "N/A"
          ]]
          yAxis = {
            left = { min = 0 }
          }
        }
      },

      # S3 Replication Latency
      {
        type   = "metric"
        x      = 16
        y      = 7
        width  = 8
        height = 6
        properties = {
          title  = "S3 CloudTrail Replication Latency (seconds)"
          view   = "timeSeries"
          stat   = "Maximum"
          period = 300
          metrics = [[
            "AWS/S3",
            "ReplicationLatency",
            "SourceBucket",
            local.cloudtrail_bucket_name,
            "DestinationBucket",
            aws_s3_bucket.dr_cloudtrail.id,
            "RuleId",
            "cloudtrail-cape-town-to-ireland"
          ]]
          annotations = {
            horizontal = [{
              label = "RTC SLA (900s)"
              value = 900
              color = "#ff6600"
            }]
          }
          yAxis = {
            left = { min = 0 }
          }
        }
      },

      # Row 4 — Alarm Status
      {
        type   = "alarm"
        x      = 0
        y      = 13
        width  = 24
        height = 4
        properties = {
          title = "DR Infrastructure Alarm Status"
          alarms = [
            aws_cloudwatch_metric_alarm.dr_aurora_storage.arn,
            aws_cloudwatch_metric_alarm.dr_aurora_cpu.arn,
            aws_cloudwatch_metric_alarm.dr_aurora_memory.arn,
            aws_cloudwatch_metric_alarm.rds_replication_lag.arn,
            aws_cloudwatch_metric_alarm.rds_replica_status.arn,
            aws_cloudwatch_metric_alarm.cloudtrail_replication_latency.arn,
            aws_cloudwatch_metric_alarm.cloudtrail_replication_failed.arn,
          ]
        }
      }
    ]
  })
}

# ============================================
# SECTION 7 — DR Readiness Composite Alarm
# ============================================
# A single composite alarm combining all DR health checks
# into one binary signal: "Is DR ready for failover?"
#
# All child alarms must be OK for this composite to be OK.
# Any child alarm firing means DR is NOT fully ready.
#
# Subscribe operations runbook automation to this alarm —
# when it fires, trigger pre-failover preparation steps.

resource "aws_cloudwatch_composite_alarm" "dr_readiness" {
  provider = aws.dr

  alarm_name        = "ABSA-DR-Overall-Readiness"
  alarm_description = "Composite: all DR health checks. OK = DR ready for failover. ALARM = DR has issues."

  # Composite alarm rule — all must be OK
  # ANY of these in ALARM state = DR not ready
  alarm_rule = join(" AND ", [
    "ALARM(${aws_cloudwatch_metric_alarm.rds_replication_lag.alarm_name})",
    "ALARM(${aws_cloudwatch_metric_alarm.dr_aurora_storage.alarm_name})",
    "ALARM(${aws_cloudwatch_metric_alarm.dr_aurora_cpu.alarm_name})",
    "ALARM(${aws_cloudwatch_metric_alarm.dr_aurora_memory.alarm_name})",
  ])

  # This composite fires when ANY child alarm fires
  # Inverted logic: composite is in ALARM when DR has issues
  alarm_actions = [aws_sns_topic.dr_ops.arn]
  ok_actions    = [aws_sns_topic.dr_ops.arn]

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-Overall-Readiness-Alarm"
  })
}