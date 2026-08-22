# ============================================
# EKS Node Group — Worker Nodes
# ============================================

# Launch Template — Required for custom KMS key on EBS volumes
resource "aws_launch_template" "payment_workers" {
  name = "absa-payment-workers"

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.eks_node_disk_size
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = local.kms_ebs_arn
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "ABSA-Payment-Worker"
    })
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Node Group — Payment processing worker nodes
resource "aws_eks_node_group" "payment_workers" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "payment-workers"
  node_role_arn   = local.eks_node_role_arn
  subnet_ids      = local.app_subnet_ids
  instance_types  = var.eks_node_instance_types
  capacity_type   = "ON_DEMAND"

  # Launch template — provides custom KMS key for EBS encryption
  launch_template {
    id      = aws_launch_template.payment_workers.id
    version = aws_launch_template.payment_workers.latest_version
  }

  # Scaling configuration
  scaling_config {
    desired_size = var.eks_node_desired_size
    min_size     = var.eks_node_min_size
    max_size     = var.eks_node_max_size
  }

  # Update configuration — rolling updates, no downtime
  update_config {
    max_unavailable_percentage = 33
  }

  # Labels for Kubernetes scheduling
  labels = {
    workload_type = "payment-processing"
    environment   = var.environment
    cost_center   = "payments"
  }

  depends_on = [
    aws_eks_addon.vpc_cni,
    aws_eks_addon.coredns,
    aws_eks_addon.kube_proxy
  ]

  tags = merge(local.common_tags, {
    Name        = "ABSA-Payment-Workers"
    WorkloadType = "Payment-Processing"
    SubnetTier   = "Application"
  })
}

# ============================================
# Kubernetes Namespaces — Microservice Isolation
# ============================================

resource "kubernetes_namespace" "namespaces" {
  for_each = toset(local.namespaces)

  metadata {
    name = each.key
    labels = {
      environment = var.environment
      managed_by  = "terraform"
    }
    annotations = {
      description = "ABSA ${each.key} microservices"
    }
  }
}

# ============================================
# Kubernetes Service Account — Payment API (IRSA)
# ============================================

resource "kubernetes_service_account" "payment_api" {
  metadata {
    name      = "payment-api-sa"
    namespace = "payment-api"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.payment_api_pod.arn
    }
  }

  depends_on = [kubernetes_namespace.namespaces]
}

# ============================================
# Kubernetes ConfigMap — Payment API Configuration
# ============================================

resource "kubernetes_config_map" "payment_api" {
  metadata {
    name      = "payment-api-config"
    namespace = "payment-api"
  }

  data = {
    "RDS_SECRET_ARN"    = local.rds_secret_arn
    "REDIS_SECRET_ARN"  = local.redis_secret_arn
    "REGION"            = var.primary_region
    "ENVIRONMENT"       = var.environment
    "LOG_LEVEL"         = "INFO"
    "FRAUD_CHECK_TOPIC" = "ABSA-Payment-Events"
  }

  depends_on = [kubernetes_namespace.namespaces]
}

# ============================================
# Kubernetes Secret — Database Connection (Metadata Only)
# ============================================

resource "kubernetes_secret" "rds_connection" {
  metadata {
    name      = "rds-connection"
    namespace = "payment-api"
  }

  data = {
    "DATABASE_HOST" = aws_rds_cluster.main.endpoint
    "DATABASE_PORT" = tostring(var.rds_port)
    "DATABASE_NAME" = var.rds_database_name
    "DATABASE_USER" = var.rds_master_username
  }

  type = "Opaque"

  depends_on = [kubernetes_namespace.namespaces]
}

# ============================================
# Kubernetes Secret — Redis Connection (Metadata Only)
# ============================================

resource "kubernetes_secret" "redis_connection" {
  metadata {
    name      = "redis-connection"
    namespace = "payment-api"
  }

  data = {
    "REDIS_HOST" = aws_elasticache_replication_group.main.primary_endpoint_address
    "REDIS_PORT" = tostring(var.redis_port)
  }

  type = "Opaque"

  depends_on = [kubernetes_namespace.namespaces]
}

# ============================================
# Kubernetes Horizontal Pod Autoscaler — Payment API
# ============================================

resource "kubernetes_horizontal_pod_autoscaler" "payment_api" {
  metadata {
    name      = "payment-api-hpa"
    namespace = "payment-api"
  }

  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = "payment-api"
    }

    min_replicas = 2
    max_replicas = 20

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type               = "Utilization"
          average_utilization = 70
        }
      }
    }

    metric {
      type = "Resource"
      resource {
        name = "memory"
        target {
          type               = "Utilization"
          average_utilization = 80
        }
      }
    }
  }

  depends_on = [kubernetes_namespace.namespaces]
}

# ============================================
# Kubernetes Pod Disruption Budget — Payment API
# ============================================

resource "kubernetes_pod_disruption_budget" "payment_api" {
  metadata {
    name      = "payment-api-pdb"
    namespace = "payment-api"
  }

  spec {
    min_available = 2
    selector {
      match_labels = {
        app = "payment-api"
      }
    }
  }

  depends_on = [kubernetes_namespace.namespaces]
}