# ============================================
# RDS Aurora PostgreSQL — Encrypted Banking Database
# ============================================

# DB Subnet Group — Which subnets RDS can use
resource "aws_db_subnet_group" "main" {
  name        = "absa-production-aurora-subnet"
  description = "Subnet group for ABSA Production Aurora cluster"
  subnet_ids  = local.data_subnet_ids

  tags = merge(local.common_tags, {
    Name = "ABSA-Aurora-Subnet-Group"
  })
}

# RDS Aurora Cluster — The database itself
resource "aws_rds_cluster" "main" {
  cluster_identifier     = var.rds_cluster_name
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.main.name
  engine                 = var.rds_engine
  engine_version         = var.rds_engine_version
  database_name          = var.rds_database_name
  master_username        = var.rds_master_username
  master_password        = random_password.rds_master.result
  port                   = var.rds_port
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [local.data_security_group_id]

  # Encryption — Using Week 3 KMS key
  storage_encrypted   = true
  kms_key_id          = local.kms_rds_arn

  # Backup configuration
  backup_retention_period = var.rds_backup_retention_days
  preferred_backup_window = "02:00-03:00"
  preferred_maintenance_window = "sun:03:00-sun:04:00"

  # Protection
  deletion_protection = var.rds_deletion_protection
  skip_final_snapshot = false
  final_snapshot_identifier = "${var.rds_cluster_name}-final-snapshot"

  # High availability
  enabled_cloudwatch_logs_exports = ["postgresql"]

  # IAM database authentication
  iam_database_authentication_enabled = true

  # Performance Insights
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = local.kms_rds_arn
  performance_insights_retention_period = 7

  tags = merge(local.common_tags, {
    Name = var.rds_cluster_name
  })

  depends_on = [aws_db_subnet_group.main]
}

# Aurora Cluster Instance — Primary
resource "aws_rds_cluster_instance" "primary" {
  identifier         = "${var.rds_cluster_name}-primary"
  cluster_identifier = aws_rds_cluster.main.id
  instance_class     = var.rds_instance_class
  engine             = var.rds_engine
  engine_version     = var.rds_engine_version

  # Performance Insights
  performance_insights_enabled = true
  performance_insights_kms_key_id = local.kms_rds_arn

  # Monitoring
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  tags = merge(local.common_tags, {
    Name = "${var.rds_cluster_name}-primary"
  })
}

# Aurora Cluster Instance — Replica 1 (different AZ)
resource "aws_rds_cluster_instance" "replica_1" {
  count              = var.enable_multi_az_rds ? 1 : 0
  identifier         = "${var.rds_cluster_name}-replica-1"
  cluster_identifier = aws_rds_cluster.main.id
  instance_class     = var.rds_instance_class
  engine             = var.rds_engine
  engine_version     = var.rds_engine_version

  performance_insights_enabled = true
  performance_insights_kms_key_id = local.kms_rds_arn

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  tags = merge(local.common_tags, {
    Name = "${var.rds_cluster_name}-replica-1"
  })
}

# Random password for RDS master — Generated at creation time
resource "random_password" "rds_master" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
  min_special      = 4
  min_upper        = 4
  min_lower        = 4
  min_numeric      = 4
}

# Store RDS password in Secrets Manager
resource "aws_secretsmanager_secret_version" "rds_master" {
  secret_id     = local.rds_secret_arn
  secret_string = jsonencode({
    username = var.rds_master_username
    password = random_password.rds_master.result
    engine   = var.rds_engine
    host     = aws_rds_cluster.main.endpoint
    host_ro  = aws_rds_cluster.main.reader_endpoint
    port     = tostring(var.rds_port)
  })
}

# IAM Role for RDS Enhanced Monitoring
resource "aws_iam_role" "rds_monitoring" {
  name = "ABSA-RDS-Monitoring-Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "ABSA-RDS-Monitoring-Role"
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

#============================================================
#parameters
#============================================================
resource "aws_rds_cluster_parameter_group" "main" {
  family      = "aurora-postgresql16"
  name        = "absa-production-aurora-params"
  description = "Custom parameter group for ABSA Aurora PostgreSQL"

  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  parameter {
    name  = "shared_buffers"
    value = "{DBInstanceClassMemory/32768}"
  }

  parameter {
    name  = "max_connections"
    value = "500"
  }
}
#=============================================================
     #cloud watch
#===========================================================
resource "aws_cloudwatch_metric_alarm" "aurora_cpu" {
  alarm_name          = "ABSA-Aurora-CPU-High"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"
  alarm_description   = "Aurora CPU above 80% for 10 minutes — investigate slow queries"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.main.cluster_identifier
  }

  tags = merge(local.common_tags, {
    Name = "ABSA-Aurora-CPU-High"
  })
}

resource "aws_cloudwatch_metric_alarm" "aurora_connections" {
  alarm_name          = "ABSA-Aurora-Connections-High"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 400
  treat_missing_data  = "notBreaching"
  alarm_description   = "Aurora connections above 400 — approaching max_connections limit"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.main.cluster_identifier
  }

  tags = merge(local.common_tags, {
    Name = "ABSA-Aurora-Connections-High"
  })
}