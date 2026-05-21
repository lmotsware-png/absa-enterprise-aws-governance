# ============================================
# Staging VPC - Pre-Production Validation
# ============================================

resource "aws_vpc" "staging" {
  cidr_block                           = var.vpc_cidrs.staging
  instance_tenancy                     = "default"
  enable_dns_support                   = true
  enable_dns_hostnames                 = true
  enable_network_address_usage_metrics = true

  tags = merge(local.common_tags, {
    Name        = "ABSA-Staging-VPC"
    Environment = "Staging"
    DataClass   = "Internal-Test"
  })
}

resource "aws_internet_gateway" "staging" {
  vpc_id = aws_vpc.staging.id

  tags = { Name = "ABSA-Staging-IGW" }
}

resource "aws_eip" "staging_nat" {
  count  = var.create_nat_gateways ? length(var.availability_zones) : 0
  domain = "vpc"

  tags = {
    Name = "ABSA-Staging-NAT-EIP-${element(var.availability_zones, count.index)}"
  }
}

resource "aws_nat_gateway" "staging" {
  count         = var.create_nat_gateways ? length(var.availability_zones) : 0
  allocation_id = aws_eip.staging_nat[count.index].id
  subnet_id     = aws_subnet.staging_public[count.index].id

  tags = {
    Name = "ABSA-Staging-NAT-${element(var.availability_zones, count.index)}"
  }

  depends_on = [aws_internet_gateway.staging]
}

resource "aws_subnet" "staging_public" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.staging.id
  cidr_block              = cidrsubnet(var.vpc_cidrs.staging, 8, count.index + local.tier_offsets.public.start)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "ABSA-Staging-Public-${element(var.availability_zones, count.index)}"
    Tier = "Public"
  }
}

resource "aws_subnet" "staging_app" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.staging.id
  cidr_block        = cidrsubnet(var.vpc_cidrs.staging, 8, count.index + local.tier_offsets.app.start)
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "ABSA-Staging-App-${element(var.availability_zones, count.index)}"
    Tier = "Application"
  }
}

resource "aws_subnet" "staging_data" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.staging.id
  cidr_block        = cidrsubnet(var.vpc_cidrs.staging, 8, count.index + local.tier_offsets.data.start)
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "ABSA-Staging-Data-${element(var.availability_zones, count.index)}"
    Tier = "Data"
  }
}

resource "aws_subnet" "staging_endpoints" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.staging.id
  cidr_block        = cidrsubnet(var.vpc_cidrs.staging, 8, count.index + local.tier_offsets.endpoints.start)
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "ABSA-Staging-Endpoints-${element(var.availability_zones, count.index)}"
    Tier = "VPC-Endpoints"
  }
}

resource "aws_route_table" "staging_public" {
  vpc_id = aws_vpc.staging.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.staging.id
  }

  tags = { Name = "ABSA-Staging-Public-RT" }
}

resource "aws_route_table" "staging_app" {
  count  = length(var.availability_zones)
  vpc_id = aws_vpc.staging.id

  dynamic "route" {
    for_each = var.create_nat_gateways ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.staging[count.index].id
    }
  }

  tags = {
    Name = "ABSA-Staging-App-RT-${element(var.availability_zones, count.index)}"
  }
}

resource "aws_route_table" "staging_data" {
  vpc_id = aws_vpc.staging.id

  tags = { Name = "ABSA-Staging-Data-RT" }
}

resource "aws_route_table_association" "staging_public" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.staging_public[count.index].id
  route_table_id = aws_route_table.staging_public.id
}

resource "aws_route_table_association" "staging_app" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.staging_app[count.index].id
  route_table_id = aws_route_table.staging_app[count.index].id
}

resource "aws_route_table_association" "staging_data" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.staging_data[count.index].id
  route_table_id = aws_route_table.staging_data.id
}

resource "aws_ec2_transit_gateway_vpc_attachment" "staging" {
  subnet_ids         = aws_subnet.staging_endpoints[*].id
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = aws_vpc.staging.id

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = { Name = "ABSA-Staging-TGW-Attachment" }
}

resource "aws_ec2_transit_gateway_route_table_association" "staging" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.staging.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.staging_to_shared.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "staging" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.staging.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.staging_to_shared.id
}

# Staging can reach Shared Services and Production (for testing)
resource "aws_route" "staging_to_shared_via_tgw" {
  route_table_id         = aws_route_table.staging_app[0].id
  destination_cidr_block = var.vpc_cidrs.devops
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
}

resource "aws_route" "staging_to_production_via_tgw" {
  route_table_id         = aws_route_table.staging_app[0].id
  destination_cidr_block = var.vpc_cidrs.production
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
}