# ============================================
# EKS Cluster — Kubernetes Control Plane
# ============================================

# CloudWatch Log Group for EKS control plane logs
resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${var.eks_cluster_name}/cluster"
  retention_in_days = 90

  tags = merge(local.common_tags, {
    Name = "ABSA-EKS-Cluster-Logs"
  })
}

# EKS Cluster — The Kubernetes control plane
resource "aws_eks_cluster" "main" {
  name     = var.eks_cluster_name
  version  = var.eks_cluster_version
  role_arn = local.eks_cluster_role_arn

  # Enable all control plane logging for security and audit
  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  # VPC configuration — cluster endpoint access
  vpc_config {
    subnet_ids              = local.app_subnet_ids
    endpoint_private_access = true   # Access from within VPC
    endpoint_public_access  = false  # No public internet access
    security_group_ids      = [local.app_security_group_id]
  }

  # Encryption at rest for Kubernetes secrets using KMS
  encryption_config {
    provider {
      key_arn = local.kms_eks_arn
    }
    resources = ["secrets"]
  }

  depends_on = [
    aws_cloudwatch_log_group.eks,
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]

  tags = merge(local.common_tags, {
    Name = var.eks_cluster_name
  })
}

# EKS Cluster Policy Attachment — Required for cluster to manage AWS resources
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = local.eks_cluster_role_arn
}

# EKS Cluster Service Policy Attachment
resource "aws_iam_role_policy_attachment" "eks_service_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = local.eks_cluster_role_arn
}

# ============================================
# EKS Add-ons — Essential cluster components
# ============================================

# VPC CNI — Pod networking
resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = local.eks_addons.vpc_cni

  depends_on = [aws_eks_cluster.main]

  tags = merge(local.common_tags, {
    Name = "ABSA-EKS-VPC-CNI"
  })
}

# CoreDNS — Cluster DNS resolution
resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = local.eks_addons.coredns

  depends_on = [aws_eks_cluster.main]

  tags = merge(local.common_tags, {
    Name = "ABSA-EKS-CoreDNS"
  })
}

# Kube-proxy — Network proxy for services
resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = local.eks_addons.kube_proxy

  depends_on = [aws_eks_cluster.main]

  tags = merge(local.common_tags, {
    Name = "ABSA-EKS-Kube-Proxy"
  })
}

# ============================================
# IRSA — IAM Roles for Service Accounts
# ============================================

# OIDC Provider — Allows pods to assume IAM roles via Kubernetes service accounts
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = merge(local.common_tags, {
    Name = "ABSA-EKS-OIDC-Provider"
  })
}

# IRSA Role — Payment API Pod
# This is HOW pods get their own IAM credentials (not using the node role)
resource "aws_iam_role" "payment_api_pod" {
  name = "ABSA-Payment-API-Pod-Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:payment-api:payment-api-sa"
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "ABSA-Payment-API-Pod-Role"
  })
}

# Payment API Pod Policy — What the pod can do
resource "aws_iam_role_policy" "payment_api_pod" {
  name = "ABSA-Payment-API-Pod-Policy"
  role = aws_iam_role.payment_api_pod.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          local.rds_secret_arn,
          local.redis_secret_arn,
          local.api_secret_arn 
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = [local.kms_secrets_arn]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage"
        ]
        Resource = "*"
      }
    ]
  })
}

# ============================================
# IRSA Role — Fraud Detection Pod
# ============================================
resource "aws_iam_role" "fraud_detection_pod" {
  name = "ABSA-Fraud-Detection-Pod-Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:fraud-detection:fraud-detection-sa"
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "ABSA-Fraud-Detection-Pod-Role"
  })
}

# Fraud Detection Pod Policy — What the pod can do
resource "aws_iam_role_policy" "fraud_detection_pod" {
  name = "ABSA-Fraud-Detection-Pod-Policy"
  role = aws_iam_role.fraud_detection_pod.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Read fraud scoring model credentials and DB access
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          local.rds_secret_arn,      # read transaction data for scoring
          local.redis_secret_arn,    # cache fraud scores
        
        ]
      },
      {
        # Decrypt secrets from Secrets Manager
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = [local.kms_secrets_arn]
      },
      {
        # Read from fraud detection SQS queue (consume payment events)
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl"
        ]
        Resource = [
          "arn:aws:sqs:${var.primary_region}:${data.aws_caller_identity.current.account_id}:absa-fraud-detection-queue"
        ]
      },
      {
        # Publish HIGH RISK fraud alerts to SNS
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = [
          "arn:aws:sns:${var.primary_region}:${data.aws_caller_identity.current.account_id}:ABSA-Fraud-Alerts"
        ]
      },
      {
        # Write fraud scoring results to CloudWatch for monitoring
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "ABSA/FraudDetection"
          }
        }
      }
    ]
  })
}