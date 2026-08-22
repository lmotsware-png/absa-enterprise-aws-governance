# ============================================
# EKS Warm Standby — DR Cluster in eu-west-1
# ============================================
#
# Design philosophy: WARM STANDBY
#   - Cluster exists and is healthy at all times
#   - One worker node running (not full production capacity)
#   - All system pods running and verified
#   - Application pods deployed at minimum replica count
#   - DR Aurora replica verified reachable on startup
#   - On failover: scale node group to production count,
#     promote Aurora replica, update application config
#
# Warm standby vs cold standby vs hot standby:
#   Cold:  nothing running, provision on failover (30-60min RTO)
#   Warm:  minimal running, scale on failover (5-15min RTO)
#   Hot:   full capacity always running (seconds RTO, 3× cost)
#
# This file produces aws_lb.dr_nlb which route53_failover.tf
# references for the DR CloudFront origin.
#
# All resources use provider = aws.dr (eu-west-1)
# except IAM resources which are global
# ============================================

# ============================================
# SECTION 1 — IAM Roles for EKS
# ============================================
# IAM is a global service — no provider = aws.dr needed.
# The DR EKS cluster and its nodes use dedicated IAM roles
# rather than sharing the primary cluster's roles, following
# the principle of least privilege and blast-radius isolation.
# A compromise of the DR cluster's role cannot affect the
# primary cluster's permissions.

# EKS Cluster Service Role
resource "aws_iam_role" "dr_eks_cluster" {
  name        = "ABSA-DR-EKS-Cluster-Role"
  description = "Service role for ABSA DR EKS cluster in eu-west-1"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-EKS-Cluster-Role"
  })
}

resource "aws_iam_role_policy_attachment" "dr_eks_cluster_policy" {
  role       = aws_iam_role.dr_eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "dr_eks_vpc_controller" {
  role       = aws_iam_role.dr_eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

# EKS Node Group Role
resource "aws_iam_role" "dr_eks_nodes" {
  name        = "ABSA-DR-EKS-Node-Role"
  description = "Node role for ABSA DR EKS worker nodes in eu-west-1"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-EKS-Node-Role"
  })
}

# Required policies for EKS worker nodes
resource "aws_iam_role_policy_attachment" "dr_eks_worker_node" {
  role       = aws_iam_role.dr_eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "dr_eks_cni" {
  role       = aws_iam_role.dr_eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "dr_eks_ecr_read" {
  role       = aws_iam_role.dr_eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "dr_eks_ssm" {
  role       = aws_iam_role.dr_eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ============================================
# SECTION 2 — EKS Cluster
# ============================================

resource "aws_eks_cluster" "dr" {
  provider = aws.dr
  count    = var.enable_dr_eks ? 1 : 0

  name    = "${local.primary_eks_cluster_name}-dr"
  role_arn = aws_iam_role.dr_eks_cluster.arn
  version = "1.32"

  vpc_config {
    subnet_ids = concat(
      aws_subnet.dr_app[*].id,
      aws_subnet.dr_data[*].id
    )
    security_group_ids      = [aws_security_group.dr_app.id]
    endpoint_private_access = true
    endpoint_public_access  = true

    # Restrict public API access to known CIDR ranges
    # Tighten this to your corporate egress IPs in production
    public_access_cidrs = ["0.0.0.0/0"]
  }

  # Envelope encryption for Kubernetes secrets using DR KMS key
  encryption_config {
    provider {
      key_arn = aws_kms_key.dr_eks.arn
    }
    resources = ["secrets"]
  }

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  tags = merge(local.common_tags, {
    Name = "${local.primary_eks_cluster_name}-dr"
  })

  depends_on = [
    aws_iam_role_policy_attachment.dr_eks_cluster_policy,
    aws_iam_role_policy_attachment.dr_eks_vpc_controller,
  ]
}

# ============================================
# SECTION 3 — KMS Key for DR EKS Secrets Encryption
# ============================================

resource "aws_kms_key" "dr_eks" {
  provider = aws.dr

  description             = "KMS key for DR EKS secrets encryption in eu-west-1"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-EKS-KMS-Key"
  })
}

resource "aws_kms_alias" "dr_eks" {
  provider = aws.dr

  name          = "alias/absa-dr-eks-encryption"
  target_key_id = aws_kms_key.dr_eks.key_id
}

# ============================================
# SECTION 4 — CloudWatch Log Group for EKS
# ============================================
# Must be created before the cluster to avoid a race condition
# where EKS creates the log group with default retention (never)

resource "aws_cloudwatch_log_group" "dr_eks" {
  provider = aws.dr
  count    = var.enable_dr_eks ? 1 : 0

  name              = "/aws/eks/${local.primary_eks_cluster_name}-dr/cluster"
  retention_in_days = 90

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-EKS-Logs"
  })
}

# ============================================
# SECTION 5 — OIDC Provider for IRSA
# ============================================
# Each EKS cluster has its own unique OIDC issuer URL.
# The DR cluster's OIDC provider is separate from the
# primary cluster's OIDC provider (Week 5).
# IRSA pod authentication in the DR cluster uses this
# provider — pods in DR present tokens from this issuer.

data "tls_certificate" "dr_eks" {
  count = var.enable_dr_eks ? 1 : 0
  url   = aws_eks_cluster.dr[0].identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "dr_eks" {
  count = var.enable_dr_eks ? 1 : 0

  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.dr_eks[0].certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.dr[0].identity[0].oidc[0].issuer

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-EKS-OIDC-Provider"
  })
}

# ============================================
# SECTION 6 — EKS Node Group
# ============================================
# Warm standby: var.dr_eks_node_count = 1
# One node is enough to: run system pods (vpc-cni,
# coredns, kube-proxy), keep the cluster healthy,
# verify DR database connectivity on pod startup.
#
# On failover: update desired_size to 3 (or production
# count) via terraform apply or AWS console autoscaling.
# Scale-out time: ~3 minutes for new nodes to join.

resource "aws_eks_node_group" "dr" {
  provider = aws.dr
  count    = var.enable_dr_eks ? 1 : 0

  cluster_name    = aws_eks_cluster.dr[0].name
  node_group_name = "absa-dr-nodes"
  node_role_arn   = aws_iam_role.dr_eks_nodes.arn

  subnet_ids = aws_subnet.dr_app[*].id

  # Warm standby: 1 node running, can scale to 6 on failover
  scaling_config {
    desired_size = var.dr_eks_node_count  # 1
    min_size     = 1
    max_size     = 6
  }

  # Same instance type as production (Week 5)
  # Ensures DR can handle production-equivalent load
  # immediately after failover without resize
  instance_types = ["c6i.xlarge"]

  # Bottlerocket — security-hardened OS, same as Week 5
  ami_type       = "BOTTLEROCKET_x86_64"
  capacity_type  = "ON_DEMAND"
  disk_size      = 50

  update_config {
    max_unavailable = 1
  }

  labels = {
    Environment = "dr"
    Tier        = "application"
    Region      = var.dr_region
  }

  # Taint warm standby nodes — prevents application pods
  # scheduling until failover taint is removed.
  # During normal operation: only system pods (tolerating
  # all taints) run on the DR node.
  # During failover: remove taint via kubectl or automation,
  # application pods immediately schedule.
  taint {
    key    = "dr-standby"
    value  = "true"
    effect = "NO_SCHEDULE"
  }

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-Node-Group"
  })

  depends_on = [
    aws_iam_role_policy_attachment.dr_eks_worker_node,
    aws_iam_role_policy_attachment.dr_eks_cni,
    aws_iam_role_policy_attachment.dr_eks_ecr_read,
    aws_iam_role_policy_attachment.dr_eks_ssm,
  ]
}

# ============================================
# SECTION 7 — IRSA Roles for DR Pods
# ============================================
# DR pods need the same AWS permissions as production pods
# but scoped to the DR cluster's OIDC provider.
# The IRSA role for each service account mirrors the
# production IRSA roles from Week 5 — same permissions,
# different trust relationship (DR OIDC issuer).

locals {
  dr_oidc_provider_arn = var.enable_dr_eks ? aws_iam_openid_connect_provider.dr_eks[0].arn : ""
  dr_oidc_issuer       = var.enable_dr_eks ? replace(
    aws_eks_cluster.dr[0].identity[0].oidc[0].issuer,
    "https://",
    ""
  ) : ""
}

# Payment API pod — same permissions as Week 5 payment pod
# Scoped to DR cluster's OIDC provider
resource "aws_iam_role" "dr_payment_api_pod" {
  count = var.enable_dr_eks ? 1 : 0

  name        = "ABSA-DR-PaymentAPI-Pod-Role"
  description = "IRSA role for payment-api pods in DR EKS cluster"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = local.dr_oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.dr_oidc_issuer}:sub" = "system:serviceaccount:payment-api:payment-api-sa"
          "${local.dr_oidc_issuer}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-PaymentAPI-Pod-Role"
  })
}

resource "aws_iam_role_policy" "dr_payment_api_pod" {
  count = var.enable_dr_eks ? 1 : 0

  name = "ABSA-DR-PaymentAPI-Pod-Policy"
  role = aws_iam_role.dr_payment_api_pod[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SecretsAccess"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        # DR secrets — replicated from primary or created fresh
        Resource = "arn:aws:secretsmanager:${var.dr_region}:${data.aws_caller_identity.current.account_id}:secret:absa/*"
      },
      {
        Sid    = "KMSDecrypt"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.dr_rds.arn
      },
      {
        Sid    = "SNSPublish"
        Effect = "Allow"
        Action = "sns:Publish"
        # DR SNS topics — created during DR activation
        Resource = "arn:aws:sns:${var.dr_region}:${data.aws_caller_identity.current.account_id}:ABSA-*"
      },
      {
        Sid    = "SQSOperations"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        # DR SQS queues — created during DR activation
        Resource = "arn:aws:sqs:${var.dr_region}:${data.aws_caller_identity.current.account_id}:absa-*"
      },
      {
        Sid    = "CloudWatchMetrics"
        Effect = "Allow"
        Action = "cloudwatch:PutMetricData"
        Resource = "*"
      }
    ]
  })
}

# ============================================
# SECTION 8 — DR Network Load Balancer
# ============================================
# The DR NLB is the origin target for the DR CloudFront
# distribution in route53_failover.tf.
# Traffic path during DR:
#   CloudFront → NLB → ALB → EKS pod
#
# NLB is internal — not publicly accessible directly.
# CloudFront is the only authorized path to the NLB
# (enforced by the X-Origin-Verify header check at
# the DR API Gateway / ALB layer).

resource "aws_lb" "dr_nlb" {
  provider = aws.dr
  count    = var.enable_dr_eks ? 1 : 0

  name               = "absa-dr-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = aws_subnet.dr_app[*].id

  # Preserve source IP through NLB to ALB
  enable_cross_zone_load_balancing = true

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-NLB"
  })
}

resource "aws_lb_target_group" "dr_nlb_https" {
  provider = aws.dr
  count    = var.enable_dr_eks ? 1 : 0

  name        = "absa-dr-nlb-https"
  port        = 443
  protocol    = "TCP"
  vpc_id      = aws_vpc.dr.id
  target_type = "alb"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
    path                = "/health"
    protocol            = "HTTPS"
    port                = "443"
  }

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-NLB-HTTPS-TG"
  })
}

resource "aws_lb_listener" "dr_nlb_https" {
  provider = aws.dr
  count    = var.enable_dr_eks ? 1 : 0

  load_balancer_arn = aws_lb.dr_nlb[0].arn
  port              = 443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.dr_nlb_https[0].arn
  }
}

# ============================================
# SECTION 9 — EKS Add-ons
# ============================================
# Core add-ons required for cluster function.
# Must be installed before application pods deploy.
# Versions should be pinned and updated deliberately —
# add-on updates can affect cluster stability.

resource "aws_eks_addon" "dr_vpc_cni" {
  provider = aws.dr
  count    = var.enable_dr_eks ? 1 : 0

  cluster_name      = aws_eks_cluster.dr[0].name
  addon_name        = "vpc-cni"
  addon_version     = "v1.18.0-eksbuild.1"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-EKS-VPC-CNI"
  })
}

resource "aws_eks_addon" "dr_coredns" {
  provider = aws.dr
  count    = var.enable_dr_eks ? 1 : 0

  cluster_name      = aws_eks_cluster.dr[0].name
  addon_name        = "coredns"
  addon_version     = "v1.11.3-eksbuild.1"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-EKS-CoreDNS"
  })

  depends_on = [aws_eks_node_group.dr]
}

resource "aws_eks_addon" "dr_kube_proxy" {
  provider = aws.dr
  count    = var.enable_dr_eks ? 1 : 0

  cluster_name      = aws_eks_cluster.dr[0].name
  addon_name        = "kube-proxy"
  addon_version     = "v1.32.0-eksbuild.2"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-EKS-KubeProxy"
  })
}

resource "aws_eks_addon" "dr_pod_identity" {
  provider = aws.dr
  count    = var.enable_dr_eks ? 1 : 0

  cluster_name      = aws_eks_cluster.dr[0].name
  addon_name        = "eks-pod-identity-agent"
  addon_version     = "v1.3.2-eksbuild.2"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-EKS-PodIdentity"
  })
}