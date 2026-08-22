# ============================================
# RDS Cross-Region Read Replica — DR Database
# ============================================

# SNS Topic for DR alerts — referenced by CloudWatch alarms
resource "aws_sns_topic" "dr_alerts" {
  provider = aws.dr

  name              = "ABSA-DR-Alerts"
  kms_master_key_id = aws_kms_key.dr_rds.id

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-Alerts"
  })
}

# DB Subnet Group in DR region
resource "aws_db_subnet_group" "dr" {
  provider = aws.dr

  name        = "absa-dr-aurora-subnet"
  description = "Subnet group for ABSA DR Aurora cluster in eu-west-1"
  subnet_ids  = aws_subnet.dr_data[*].id

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-Aurora-Subnet-Group"
  })
}

# ============================================
# KMS Key for DR Region — RDS Encryption
# ============================================

resource "aws_kms_key" "dr_rds" {
  provider = aws.dr

  description             = "KMS key for DR RDS encryption in eu-west-1"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-RDS-KMS-Key"
  })
}

resource "aws_kms_alias" "dr_rds" {
  provider = aws.dr

  name          = "alias/absa-dr-rds-encryption"
  target_key_id = aws_kms_key.dr_rds.key_id
}

# ============================================
# RDS Aurora Cross-Region Read Replica
# ============================================

resource "aws_rds_cluster" "dr" {
  provider = aws.dr

  cluster_identifier = "absa-dr-aurora"
  engine             = "aurora-postgresql"
  engine_version     = "16.4"

  # Declares this is a cross-region replica of the Cape Town primary
  # Terraform constructs the full ARN: arn:aws:rds:af-south-1:<account>:cluster:<id>
  replication_source_identifier = "arn:aws:rds:${var.primary_region}:${data.aws_caller_identity.current.account_id}:cluster:${local.primary_rds_cluster_id}"

  # Encryption using dedicated DR KMS key
  storage_encrypted = true
  kms_key_id        = aws_kms_key.dr_rds.arn

  # Network placement in DR data subnets
  db_subnet_group_name   = aws_db_subnet_group.dr.name
  vpc_security_group_ids = [aws_security_group.dr_data.id]

  # Snapshot protection — DR data is production data
  skip_final_snapshot           = false
  final_snapshot_identifier     = "absa-dr-aurora-final-snapshot"
  backup_retention_period       = 7
  preferred_backup_window       = "02:00-03:00"
  preferred_maintenance_window  = "sun:03:00-sun:04:00"

  # Deletion protection on DR cluster
  deletion_protection = true

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-Aurora"
  })
}

# DR Cluster Instance — warm standby, one instance
resource "aws_rds_cluster_instance" "dr" {
  provider = aws.dr

  identifier         = "absa-dr-aurora-instance"
  cluster_identifier = aws_rds_cluster.dr.id
  instance_class     = "db.r6g.large"
  engine             = "aurora-postgresql"
  engine_version     = "16.4"

  # Performance Insights — monitor DR instance health
  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.dr_rds.arn

  # Enhanced monitoring
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_dr_monitoring.arn

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-Aurora-Instance"
  })
}

# ============================================
# IAM Role for DR RDS Enhanced Monitoring
# ============================================

resource "aws_iam_role" "rds_dr_monitoring" {
  provider = aws.dr
  name     = "ABSA-DR-RDS-Monitoring-Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-RDS-Monitoring-Role"
  })
}

resource "aws_iam_role_policy_attachment" "rds_dr_monitoring" {
  provider   = aws.dr
  role       = aws_iam_role.rds_dr_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ============================================
# CloudWatch Alarms — Replication Health
# ============================================

# PRIMARY ALARM: Replication lag exceeding RPO target
resource "aws_cloudwatch_metric_alarm" "rds_replication_lag" {
  provider = aws.dr

  alarm_name          = "ABSA-DR-RDS-Replication-Lag"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "AuroraBinlogReplicaLag"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Maximum"
  threshold           = var.rds_replication_lag_alert_threshold
  alarm_description   = "DR RDS replication lag exceeds ${var.rds_replication_lag_alert_threshold}s — data loss risk exceeds RPO target"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.dr.cluster_identifier
  }

  # Alert the DR operations SNS topic
  alarm_actions = [aws_sns_topic.dr_alerts.arn]
  ok_actions    = [aws_sns_topic.dr_alerts.arn]

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-RDS-Replication-Lag-Alarm"
  })
}

# SECONDARY ALARM: Replication has stopped entirely
resource "aws_cloudwatch_metric_alarm" "rds_replica_status" {
  provider = aws.dr

  alarm_name          = "ABSA-DR-RDS-Replica-Not-Replicating"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 1
  treat_missing_data  = "breaching"
  alarm_description   = "DR RDS replica has no database connections — replication may have stopped"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.dr.cluster_identifier
  }

  alarm_actions = [aws_sns_topic.dr_alerts.arn]

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-RDS-Replica-Status-Alarm"
  })
}