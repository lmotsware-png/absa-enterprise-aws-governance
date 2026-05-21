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
  }

  tags = merge(local.common_tags, {
    Name = "ABSA-VPC-Endpoints-SG"
  })
}

# ALB Security Group (Placeholder for Week 4)
resource "aws_security_group" "alb" {
  name        = "ABSA-ALB-SG"
  description = "Application Load Balancer security group"
  vpc_id      = aws_vpc.production.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS from internet"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP redirect to HTTPS"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "ABSA-ALB-SG"
  })
}

# Baseline Application Security Group
resource "aws_security_group" "baseline_app" {
  name        = "ABSA-Baseline-App-SG"
  description = "Baseline security group for application tier"
  vpc_id      = aws_vpc.production.id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "Application traffic from ALB"
  }

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
    description = "Allow all outbound (controlled by route tables)"
  }

  tags = merge(local.common_tags, {
    Name = "ABSA-Baseline-App-SG"
  })
}

# Data Tier Security Group
resource "aws_security_group" "baseline_data" {
  name        = "ABSA-Baseline-Data-SG"
  description = "Security group for data tier (RDS, ElastiCache)"
  vpc_id      = aws_vpc.production.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.baseline_app.id]
    description     = "PostgreSQL from app tier"
  }

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.baseline_app.id]
    description     = "Redis from app tier"
  }

  tags = merge(local.common_tags, {
    Name = "ABSA-Baseline-Data-SG"
  })
}