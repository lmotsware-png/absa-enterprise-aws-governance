# ============================================
# DR VPC — eu-west-1 (Ireland)
# ============================================
#
# Mirrors the Week 2 production VPC structure exactly:
#   Three-tier subnet architecture across three AZs
#   Public tier:      10.101.1.0/24  - 10.101.3.0/24
#   Application tier: 10.101.11.0/24 - 10.101.13.0/24
#   Data tier:        10.101.21.0/24 - 10.101.23.0/24
#
# CIDR offset rule: 10.1.x.x (primary) → 10.101.x.x (DR)
# The 100-offset in the second octet makes every DR address
# mentally translatable from its primary equivalent.
# Enables VPC peering: non-overlapping CIDRs required.
#
# All resources use provider = aws.dr (eu-west-1)
# ============================================

# ============================================
# SECTION 1 — VPC
# ============================================

resource "aws_vpc" "dr" {
  provider = aws.dr

  cidr_block           = local.dr_vpc_cidr  # 10.101.0.0/16
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-VPC"
  })
}

# ============================================
# SECTION 2 — Internet Gateway
# ============================================
# Required for: NAT Gateway outbound path,
# public subnet resources (future NLB if needed),
# VPC peering route traffic to primary region

resource "aws_internet_gateway" "dr" {
  provider = aws.dr
  vpc_id   = aws_vpc.dr.id

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-IGW"
  })
}

# ============================================
# SECTION 3 — Public Subnets
# ============================================
# Three subnets, one per AZ in eu-west-1.
# Hosts: NAT Gateways, future public-facing NLB
# if DR architecture evolves to direct NLB exposure.
# Currently NAT Gateways are the primary residents.

resource "aws_subnet" "dr_public" {
  provider = aws.dr
  count    = length(local.dr_availability_zones)

  vpc_id                  = aws_vpc.dr.id
  cidr_block              = local.dr_public_subnets[count.index]
  availability_zone       = local.dr_availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-Public-${local.dr_availability_zones[count.index]}"
    Tier = "Public"
  })
}

# ============================================
# SECTION 4 — Application Subnets
# ============================================
# Three subnets, one per AZ in eu-west-1.
# Hosts: DR EKS worker nodes, Lambda functions,
# any compute resources that need outbound internet
# access via NAT Gateway but no inbound public access.
# Mirrors primary 10.1.11-13.0/24 → DR 10.101.11-13.0/24

resource "aws_subnet" "dr_app" {
  provider = aws.dr
  count    = length(local.dr_availability_zones)

  vpc_id                  = aws_vpc.dr.id
  cidr_block              = local.dr_app_subnets[count.index]
  availability_zone       = local.dr_availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-App-${local.dr_availability_zones[count.index]}"
    Tier = "Application"
    # EKS requires this tag to discover subnets for node placement
    "kubernetes.io/role/internal-elb" = "1"
  })
}

# ============================================
# SECTION 5 — Data Subnets
# ============================================
# Three subnets, one per AZ in eu-west-1.
# Hosts: DR Aurora replica, DR Redis (if added),
# DR Amazon MQ (if added), DR OpenSearch (if added).
# No internet route — most isolated tier.
# Referenced by rds_cross_region.tf via aws_subnet.dr_data[*].id
# Mirrors primary 10.1.21-23.0/24 → DR 10.101.21-23.0/24

resource "aws_subnet" "dr_data" {
  provider = aws.dr
  count    = length(local.dr_availability_zones)

  vpc_id                  = aws_vpc.dr.id
  cidr_block              = local.dr_data_subnets[count.index]
  availability_zone       = local.dr_availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-Data-${local.dr_availability_zones[count.index]}"
    Tier = "Data"
  })
}

# ============================================
# SECTION 6 — Elastic IPs for NAT Gateways
# ============================================
# One EIP per AZ — single NAT Gateway per AZ pattern.
# Three NAT Gateways provides AZ-level resilience:
# if eu-west-1a fails, app tier in eu-west-1b/c still
# has outbound internet via their own NAT Gateways.
# Cost: ~$32/month per NAT Gateway × 3 = ~$96/month.
# Acceptable for production DR warm standby.

resource "aws_eip" "dr_nat" {
  provider = aws.dr
  count    = length(local.dr_availability_zones)

  domain     = "vpc"
  depends_on = [aws_internet_gateway.dr]

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-NAT-EIP-${local.dr_availability_zones[count.index]}"
  })
}

# ============================================
# SECTION 7 — NAT Gateways
# ============================================
# One NAT Gateway per public subnet (per AZ).
# Application and data tier subnets route outbound
# traffic through their AZ-local NAT Gateway.
# Outbound traffic: EKS pulling container images,
# Lambda calling external APIs, Aurora calling
# AWS services (Secrets Manager, KMS, etc.)

resource "aws_nat_gateway" "dr" {
  provider = aws.dr
  count    = length(local.dr_availability_zones)

  allocation_id = aws_eip.dr_nat[count.index].id
  subnet_id     = aws_subnet.dr_public[count.index].id

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-NAT-${local.dr_availability_zones[count.index]}"
  })

  depends_on = [aws_internet_gateway.dr]
}

# ============================================
# SECTION 8 — Route Tables
# ============================================

# Public route table — routes to internet gateway
resource "aws_route_table" "dr_public" {
  provider = aws.dr
  vpc_id   = aws_vpc.dr.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.dr.id
  }

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-Public-RT"
  })
}

# Application route tables — one per AZ, routes to AZ-local NAT
resource "aws_route_table" "dr_app" {
  provider = aws.dr
  count    = length(local.dr_availability_zones)

  vpc_id = aws_vpc.dr.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.dr[count.index].id
  }

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-App-RT-${local.dr_availability_zones[count.index]}"
  })
}

# Data route tables — one per AZ, routes to AZ-local NAT
# Data tier needs NAT for: KMS API calls, Secrets Manager,
# RDS calling AWS services during maintenance.
# No direct internet route — requests go outbound via NAT only.
resource "aws_route_table" "dr_data" {
  provider = aws.dr
  count    = length(local.dr_availability_zones)

  vpc_id = aws_vpc.dr.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.dr[count.index].id
  }

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-Data-RT-${local.dr_availability_zones[count.index]}"
  })
}

# ============================================
# SECTION 9 — Route Table Associations
# ============================================

# Public subnets → public route table
resource "aws_route_table_association" "dr_public" {
  provider = aws.dr
  count    = length(local.dr_availability_zones)

  subnet_id      = aws_subnet.dr_public[count.index].id
  route_table_id = aws_route_table.dr_public.id
}

# App subnets → AZ-local app route table
resource "aws_route_table_association" "dr_app" {
  provider = aws.dr
  count    = length(local.dr_availability_zones)

  subnet_id      = aws_subnet.dr_app[count.index].id
  route_table_id = aws_route_table.dr_app[count.index].id
}

# Data subnets → AZ-local data route table
resource "aws_route_table_association" "dr_data" {
  provider = aws.dr
  count    = length(local.dr_availability_zones)

  subnet_id      = aws_subnet.dr_data[count.index].id
  route_table_id = aws_route_table.dr_data[count.index].id
}

# ============================================
# SECTION 10 — Security Groups
# ============================================
# Mirrors Week 3's baseline security group system.
# Three groups, same wristband-and-bouncer principle:
#   dr_public  — ALB/NLB layer (internet-facing)
#   dr_app     — EKS nodes, Lambda (application tier)
#   dr_data    — Aurora, Redis, MQ (data tier)
#
# Referenced by:
#   rds_cross_region.tf → aws_security_group.dr_data
#   eks_warm_standby.tf → aws_security_group.dr_app
#   route53_failover.tf → (indirectly via NLB)
# ============================================

# Public security group — internet-facing load balancers
resource "aws_security_group" "dr_public" {
  provider    = aws.dr
  name        = "absa-dr-public"
  description = "DR public tier — ALB/NLB internet-facing"
  vpc_id      = aws_vpc.dr.id

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from internet — redirected to HTTPS by ALB"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-Public-SG"
  })
}

# Application security group — EKS nodes and Lambda
resource "aws_security_group" "dr_app" {
  provider    = aws.dr
  name        = "absa-dr-app"
  description = "DR application tier — EKS nodes and compute"
  vpc_id      = aws_vpc.dr.id

  # Inbound from public tier (ALB/NLB → EKS nodes)
  ingress {
    description     = "HTTPS from public tier"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.dr_public.id]
  }

  # EKS node-to-node communication
  ingress {
    description = "All traffic within app tier for EKS pod communication"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # EKS API server communication
  ingress {
    description = "EKS API server to nodes"
    from_port   = 1025
    to_port     = 65535
    protocol    = "tcp"
    self        = true
  }

  egress {
    description = "All outbound — EKS needs to reach AWS APIs, pull images"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-App-SG"
  })
}

# Data security group — Aurora, Redis, MQ
# Referenced directly by rds_cross_region.tf
resource "aws_security_group" "dr_data" {
  provider    = aws.dr
  name        = "absa-dr-data"
  description = "DR data tier — Aurora, Redis, Amazon MQ"
  vpc_id      = aws_vpc.dr.id

  # PostgreSQL — Aurora (from app tier only)
  ingress {
    description     = "PostgreSQL from app tier"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.dr_app.id]
  }

  # Redis — ElastiCache (from app tier only)
  ingress {
    description     = "Redis from app tier"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.dr_app.id]
  }

  # ActiveMQ — OpenWire SSL (from app tier only)
  ingress {
    description     = "ActiveMQ OpenWire SSL from app tier"
    from_port       = 61617
    to_port         = 61617
    protocol        = "tcp"
    security_groups = [aws_security_group.dr_app.id]
  }

  # OpenSearch — HTTPS (from app tier only)
  ingress {
    description     = "OpenSearch HTTPS from app tier"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.dr_app.id]
  }

  egress {
    description = "Outbound for AWS API calls via NAT"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-Data-SG"
  })
}

# ============================================
# SECTION 11 — VPC Endpoints
# ============================================
# Keeps AWS API traffic inside the AWS backbone.
# Without endpoints, EKS nodes, Lambda, and Aurora
# call AWS APIs (KMS, Secrets Manager, S3, ECR)
# via NAT Gateway — adding latency and NAT cost.
# With endpoints, traffic stays on private network.
#
# Critical for DR: during failover when traffic
# volume spikes, VPC endpoints prevent NAT Gateway
# becoming a bottleneck for AWS API calls.

# S3 Gateway endpoint — free, no ENI needed
# Used by: EKS pulling ECR images, Aurora S3 exports,
# Lambda reading from S3, replication traffic
resource "aws_vpc_endpoint" "dr_s3" {
  provider      = aws.dr
  vpc_id        = aws_vpc.dr.id
  service_name  = "com.amazonaws.${var.dr_region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    [aws_route_table.dr_public.id],
    aws_route_table.dr_app[*].id,
    aws_route_table.dr_data[*].id
  )

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-S3-Endpoint"
  })
}

# DynamoDB Gateway endpoint — free
# Used by: EKS metadata, Terraform state locking
# if DR state is ever moved to eu-west-1
resource "aws_vpc_endpoint" "dr_dynamodb" {
  provider          = aws.dr
  vpc_id            = aws_vpc.dr.id
  service_name      = "com.amazonaws.${var.dr_region}.dynamodb"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    [aws_route_table.dr_public.id],
    aws_route_table.dr_app[*].id,
    aws_route_table.dr_data[*].id
  )

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-DynamoDB-Endpoint"
  })
}

# ECR endpoints — EKS pulls container images from ECR
# Without these, image pulls go via NAT Gateway
# During DR failover with traffic spike, image pulls
# must not compete with application traffic at NAT
resource "aws_vpc_endpoint" "dr_ecr_api" {
  provider            = aws.dr
  vpc_id              = aws_vpc.dr.id
  service_name        = "com.amazonaws.${var.dr_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.dr_app[*].id
  security_group_ids  = [aws_security_group.dr_app.id]

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-ECR-API-Endpoint"
  })
}

resource "aws_vpc_endpoint" "dr_ecr_dkr" {
  provider            = aws.dr
  vpc_id              = aws_vpc.dr.id
  service_name        = "com.amazonaws.${var.dr_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.dr_app[*].id
  security_group_ids  = [aws_security_group.dr_app.id]

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-ECR-DKR-Endpoint"
  })
}

# KMS endpoint — Aurora encryption calls, Secrets Manager
# decryption, S3 object encryption during replication
# Without this, every KMS call from the data tier goes
# via NAT — adds latency to every encrypted database
# operation during DR mode
resource "aws_vpc_endpoint" "dr_kms" {
  provider            = aws.dr
  vpc_id              = aws_vpc.dr.id
  service_name        = "com.amazonaws.${var.dr_region}.kms"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.dr_data[*].id
  security_group_ids  = [aws_security_group.dr_data.id]

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-KMS-Endpoint"
  })
}

# Secrets Manager endpoint — DR EKS pods retrieve
# RDS credentials, Redis auth tokens, API keys
# Same IRSA-based secrets retrieval pattern as Week 5
resource "aws_vpc_endpoint" "dr_secretsmanager" {
  provider            = aws.dr
  vpc_id              = aws_vpc.dr.id
  service_name        = "com.amazonaws.${var.dr_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.dr_app[*].id
  security_group_ids  = [aws_security_group.dr_app.id]

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-SecretsManager-Endpoint"
  })
}

# CloudWatch Logs endpoint — EKS pods, Lambda functions,
# and RDS enhanced monitoring publish logs through this
resource "aws_vpc_endpoint" "dr_logs" {
  provider            = aws.dr
  vpc_id              = aws_vpc.dr.id
  service_name        = "com.amazonaws.${var.dr_region}.logs"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.dr_app[*].id
  security_group_ids  = [aws_security_group.dr_app.id]

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-CloudWatch-Logs-Endpoint"
  })
}

# STS endpoint — IRSA token exchange for pod IAM roles
# EKS pods call STS to exchange projected service account
# tokens for AWS credentials. Without this endpoint,
# every IRSA authentication goes via NAT Gateway.
resource "aws_vpc_endpoint" "dr_sts" {
  provider            = aws.dr
  vpc_id              = aws_vpc.dr.id
  service_name        = "com.amazonaws.${var.dr_region}.sts"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.dr_app[*].id
  security_group_ids  = [aws_security_group.dr_app.id]

  tags = merge(local.common_tags, {
    Name = "ABSA-DR-STS-Endpoint"
  })
}