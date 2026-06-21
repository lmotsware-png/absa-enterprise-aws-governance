# ============================================
# Baseline Security Groups
# ============================================

# VPC Endpoint Security Group
resource "aws_security_group" "vpc_endpoints" {
  name        = "ABSA-VPC-Endpoints-SG"
  description = "Allow HTTPS inbound from all ABSA VPC CIDRs to VPC endpoints"
  vpc_id      = aws_vpc.production.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [
      var.vpc_cidrs.production,
      var.vpc_cidrs.hr,
      var.vpc_cidrs.finance,
      var.vpc_cidrs.devops,
      var.vpc_cidrs.staging,
      var.vpc_cidrs.qa
    ]
    description = "HTTPS from all ABSA VPCs"
  }

  tags = merge(local.common_tags, {
    Name = "ABSA-VPC-Endpoints-SG"
  })
}

# ALB Security Group — Front door bouncer
resource "aws_security_group" "alb" {
  name        = "ABSA-ALB-SG"
  description = "Application Load Balancer security group — allows HTTPS from internet"
  vpc_id      = aws_vpc.production.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS from internet (CloudFront, customer devices)"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP — immediately redirected to HTTPS"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(local.common_tags, {
    Name = "ABSA-ALB-SG"
  })
}

# Baseline Application Security Group — Worn by EKS pods
resource "aws_security_group" "baseline_app" {
  name        = "ABSA-Baseline-App-SG"
  description = "Security group for application tier (EKS pods) — allows traffic from ALB"
  vpc_id      = aws_vpc.production.id

  # Payment API — port 8080
  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "Payment API traffic from ALB (Sipho's transfers, balance checks)"
  }

  # Fraud Detection — port 8081 (FIXED: was missing)
  ingress {
    from_port       = 8081
    to_port         = 8081
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "Fraud detection traffic from ALB (real-time fraud scoring)"
  }

  # HTTPS — port 443
  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "HTTPS from ALB"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound (controlled by route tables, not security groups)"
  }

  tags = merge(local.common_tags, {
    Name = "ABSA-Baseline-App-SG"
  })
}

# Data Tier Security Group — Worn by RDS and Redis
resource "aws_security_group" "baseline_data" {
  name        = "ABSA-Baseline-Data-SG"
  description = "Security group for data tier (RDS, ElastiCache) — only allows traffic from app tier"
  vpc_id      = aws_vpc.production.id

  # PostgreSQL — port 5432
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.baseline_app.id]
    description     = "PostgreSQL from app tier (RDS Aurora — Sipho's transaction data)"
  }

  # Redis — port 6379
  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.baseline_app.id]
    description     = "Redis from app tier (ElastiCache — Sipho's session and cached balance)"
  }

  tags = merge(local.common_tags, {
    Name = "ABSA-Baseline-Data-SG"
  })
}
