# ============================================
# ElastiCache Redis — Session & Caching Layer
# ============================================

# Subnet Group — Which subnets Redis can use
resource "aws_elasticache_subnet_group" "main" {
  name        = "absa-production-redis-subnet"
  description = "Subnet group for ABSA Production Redis cluster"
  subnet_ids  = local.data_subnet_ids

  tags = merge(local.common_tags, {
    Name = "ABSA-Redis-Subnet-Group"
  })
}

# Parameter Group — Redis configuration
resource "aws_elasticache_parameter_group" "main" {
  name        = "absa-production-redis-params"
  family      = "redis7"
  description = "Redis parameter group for ABSA Production"

  # Eviction policy — when memory is full, evict keys with TTL first (LRU order)
  parameter {
    name  = "maxmemory-policy"
    value = "volatile-lru"
  }

  # Close idle client connections after 5 minutes
  parameter {
    name  = "timeout"
    value = "300"
  }

  # TCP keepalive probes every 60 seconds to detect dead connections
  parameter {
    name  = "tcp-keepalive"
    value = "60"
  }

  tags = merge(local.common_tags, {
    Name = "ABSA-Redis-Params"
  })
}

# Redis Replication Group — Primary + Replica
resource "aws_elasticache_replication_group" "main" {
  replication_group_id = var.redis_cluster_name
  description          = "ABSA Production Redis — Session and cache management"
  node_type            = var.redis_node_type
  port                 = var.redis_port
  parameter_group_name = aws_elasticache_parameter_group.main.name
  subnet_group_name    = aws_elasticache_subnet_group.main.name

  # Security — Four independent layers
  security_group_ids         = [local.data_security_group_id]   # Network isolation — only app tier can reach Redis
  at_rest_encryption_enabled = true                              # Data encrypted on disk (snapshots, backups)
  transit_encryption_enabled = true                              # Data encrypted in transit (TLS)
  auth_token                 = random_password.redis_auth.result # Authentication — Redis requires this password

  # High availability
  automatic_failover_enabled = var.enable_redis_multi_az
  num_cache_clusters         = var.redis_num_cache_nodes          # 2 nodes — primary + replica

  # Maintenance — UTC times (SAST = UTC+2)
  # Maintenance: Sunday 06:00-07:00 SAST
  maintenance_window = "sun:04:00-sun:05:00"
  # Snapshots: 05:00-06:00 SAST
  snapshot_window            = "03:00-04:00"
  snapshot_retention_limit   = 7                                  # 7 days of daily snapshots
  auto_minor_version_upgrade = true                               # Auto-apply minor patches
  apply_immediately          = false                               # Queue changes for maintenance window

  # Engine
  engine         = "redis"
  engine_version = var.redis_engine_version

  tags = merge(local.common_tags, {
    Name = var.redis_cluster_name
  })

  depends_on = [aws_elasticache_subnet_group.main]
}

# Random Auth Token — Generated at creation
# Alphanumeric only (special = false) because Redis AUTH has known
# sensitivities to special characters in the token
resource "random_password" "redis_auth" {
  length      = 32
  special     = false
  min_upper   = 8
  min_lower   = 8
  min_numeric = 8
}

# Store Redis auth token in Secrets Manager — Update the Week 3 container
resource "aws_secretsmanager_secret_version" "redis_auth" {
  secret_id     = local.redis_secret_arn
  secret_string = jsonencode({
    auth_token = random_password.redis_auth.result
    redis_host = aws_elasticache_replication_group.main.primary_endpoint_address
    redis_port = tostring(var.redis_port)
  })
}