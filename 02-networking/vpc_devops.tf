# ============================================
# DevOps VPC - CI/CD & Shared Tools
# ============================================

resource "aws_vpc" "devops" {
  cidr_block                           = var.vpc_cidrs.devops
  instance_tenancy                     = "default"
  enable_dns_support                   = true
  enable_dns_hostnames                 = true
  enable_network_address_usage_metrics = true

  tags = merge(local.common_tags, {
    Name        = "ABSA-DevOps-VPC"
    Environment = "Production"
    DataClass   = "Internal"
  })
}

resource "aws_internet_gateway" "devops" {
  vpc_id = aws_vpc.devops.id

  tags = { Name = "ABSA-DevOps-IGW" }
}

resource "aws_eip" "devops_nat" {
  count  = var.create_nat_gateways ? length(var.availability_zones) : 0
  domain = "vpc"

  tags = {
    Name = "ABSA-DevOps-NAT-EIP-${element(var.availability_zones, count.index)}"
  }
}

resource "aws_nat_gateway" "devops" {
  count         = var.create_nat_gateways ? length(var.availability_zones) : 0
  allocation_id = aws_eip.devops_nat[count.index].id
  subnet_id     = aws_subnet.devops_public[count.index].id

  tags = {
    Name = "ABSA-DevOps-NAT-${element(var.availability_zones, count.index)}"
  }

  depends_on = [aws_internet_gateway.devops]
}

resource "aws_subnet" "devops_public" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.devops.id
  cidr_block              = cidrsubnet(var.vpc_cidrs.devops, 8, count.index + local.tier_offsets.public.start)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "ABSA-DevOps-Public-${element(var.availability_zones, count.index)}"
    Tier = "Public"
  }
}

resource "aws_subnet" "devops_app" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.devops.id
  cidr_block        = cidrsubnet(var.vpc_cidrs.devops, 8, count.index + local.tier_offsets.app.start)
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "ABSA-DevOps-App-${element(var.availability_zones, count.index)}"
    Tier = "Application"
  }
}

resource "aws_subnet" "devops_data" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.devops.id
  cidr_block        = cidrsubnet(var.vpc_cidrs.devops, 8, count.index + local.tier_offsets.data.start)
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "ABSA-DevOps-Data-${element(var.availability_zones, count.index)}"
    Tier = "Data"
  }
}

resource "aws_subnet" "devops_endpoints" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.devops.id
  cidr_block        = cidrsubnet(var.vpc_cidrs.devops, 8, count.index + local.tier_offsets.endpoints.start)
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "ABSA-DevOps-Endpoints-${element(var.availability_zones, count.index)}"
    Tier = "VPC-Endpoints"
  }
}

resource "aws_route_table" "devops_public" {
  vpc_id = aws_vpc.devops.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.devops.id
  }

  tags = { Name = "ABSA-DevOps-Public-RT" }
}

resource "aws_route_table" "devops_app" {
  count  = length(var.availability_zones)
  vpc_id = aws_vpc.devops.id

  dynamic "route" {
    for_each = var.create_nat_gateways ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.devops[count.index].id
    }
  }

  tags = {
    Name = "ABSA-DevOps-App-RT-${element(var.availability_zones, count.index)}"
  }
}

resource "aws_route_table" "devops_data" {
  vpc_id = aws_vpc.devops.id

  tags = { Name = "ABSA-DevOps-Data-RT" }
}

resource "aws_route_table_association" "devops_public" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.devops_public[count.index].id
  route_table_id = aws_route_table.devops_public.id
}

resource "aws_route_table_association" "devops_app" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.devops_app[count.index].id
  route_table_id = aws_route_table.devops_app[count.index].id
}

resource "aws_route_table_association" "devops_data" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.devops_data[count.index].id
  route_table_id = aws_route_table.devops_data.id
}

resource "aws_ec2_transit_gateway_vpc_attachment" "devops" {
  subnet_ids         = aws_subnet.devops_endpoints[*].id
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = aws_vpc.devops.id

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = { Name = "ABSA-DevOps-TGW-Attachment" }
}

# DevOps is the Shared Services VPC
# Associate with shared_to_production for outbound to other VPCs
resource "aws_ec2_transit_gateway_route_table_association" "devops" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.devops.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.shared_to_production.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "devops" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.devops.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.shared_to_production.id
}

# Propagate DevOps to ALL other TGW route tables so they can reach shared services
resource "aws_ec2_transit_gateway_route_table_propagation" "devops_to_prod" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.devops.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.production_to_shared.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "devops_to_finance" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.devops.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.finance_to_shared.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "devops_to_dev" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.devops.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.dev_to_shared.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "devops_to_staging" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.devops.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.staging_to_shared.id
}

# DevOps VPC can reach all other VPCs (for management/monitoring)
resource "aws_route" "devops_to_production_via_tgw" {
  route_table_id         = aws_route_table.devops_app[0].id
  destination_cidr_block = var.vpc_cidrs.production
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
}

resource "aws_route" "devops_to_hr_via_tgw" {
  route_table_id         = aws_route_table.devops_app[0].id
  destination_cidr_block = var.vpc_cidrs.hr
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
}

resource "aws_route" "devops_to_finance_via_tgw" {
  route_table_id         = aws_route_table.devops_app[0].id
  destination_cidr_block = var.vpc_cidrs.finance
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
}

resource "aws_route" "devops_to_staging_via_tgw" {
  route_table_id         = aws_route_table.devops_app[0].id
  destination_cidr_block = var.vpc_cidrs.staging
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
}