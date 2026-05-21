# Production VPC — Core banking workloads
resource "aws_vpc" "production" {
  cidr_block                           = var.vpc_cidrs.production
  instance_tenancy                     = "default"
  enable_dns_support                   = true
  enable_dns_hostnames                 = true
  enable_network_address_usage_metrics = true

  tags = merge(local.common_tags, {
    Name        = "ABSA-Production-VPC"
    Environment = "Production"
    DataClass   = "PCI-DSS"
  })
}

# Internet Gateway — Public subnets only
resource "aws_internet_gateway" "production" {
  vpc_id = aws_vpc.production.id
  
  tags = {
    Name = "ABSA-Production-IGW"
  }
}

# NAT Gateways — One per AZ for HA
resource "aws_eip" "production_nat" {
  count = length(var.availability_zones)
  domain = "vpc"
  
  tags = {
    Name = "ABSA-Production-NAT-EIP-${element(var.availability_zones, count.index)}"
  }
}

resource "aws_nat_gateway" "production" {
  count         = length(var.availability_zones)
  allocation_id = aws_eip.production_nat[count.index].id
  subnet_id     = aws_subnet.production_public[count.index].id
  
  tags = {
    Name = "ABSA-Production-NAT-${element(var.availability_zones, count.index)}"
  }
  
  depends_on = [aws_internet_gateway.production]
}

# Subnets
resource "aws_subnet" "production_public" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.production.id
  cidr_block              = cidrsubnet(var.vpc_cidrs.production, 8, count.index + 1)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true
  
  tags = {
    Name = "ABSA-Production-Public-${element(var.availability_zones, count.index)}"
    Tier = "Public"
  }
}

resource "aws_subnet" "production_app" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.production.id
  cidr_block        = cidrsubnet(var.vpc_cidrs.production, 8, count.index + 11)
  availability_zone = var.availability_zones[count.index]
  
  tags = {
    Name = "ABSA-Production-App-${element(var.availability_zones, count.index)}"
    Tier = "Application"
  }
}

resource "aws_subnet" "production_data" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.production.id
  cidr_block        = cidrsubnet(var.vpc_cidrs.production, 8, count.index + 21)
  availability_zone = var.availability_zones[count.index]
  
  tags = {
    Name = "ABSA-Production-Data-${element(var.availability_zones, count.index)}"
    Tier = "Data"
  }
}

resource "aws_subnet" "production_endpoints" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.production.id
  cidr_block        = cidrsubnet(var.vpc_cidrs.production, 8, count.index + 31)
  availability_zone = var.availability_zones[count.index]
  
  tags = {
    Name = "ABSA-Production-Endpoints-${element(var.availability_zones, count.index)}"
    Tier = "VPC-Endpoints"
  }
}

# Route Tables
resource "aws_route_table" "production_public" {
  vpc_id = aws_vpc.production.id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.production.id
  }
  
  tags = {
    Name = "ABSA-Production-Public-RT"
  }
}

resource "aws_route_table" "production_app" {
  count  = length(var.availability_zones)
  vpc_id = aws_vpc.production.id
  
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.production[count.index].id
  }
  
  tags = {
    Name = "ABSA-Production-App-RT-${element(var.availability_zones, count.index)}"
  }
}

resource "aws_route_table" "production_data" {
  vpc_id = aws_vpc.production.id
  
  # Data tier has NO route to internet — neither IGW nor NAT
  # Only routes to VPC endpoints and TGW
  
  tags = {
    Name = "ABSA-Production-Data-RT"
  }
}

# Route Table Associations
resource "aws_route_table_association" "production_public" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.production_public[count.index].id
  route_table_id = aws_route_table.production_public.id
}

resource "aws_route_table_association" "production_app" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.production_app[count.index].id
  route_table_id = aws_route_table.production_app[count.index].id
}

resource "aws_route_table_association" "production_data" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.production_data[count.index].id
  route_table_id = aws_route_table.production_data.id
}

# TGW Attachment
resource "aws_ec2_transit_gateway_vpc_attachment" "production" {
  subnet_ids         = aws_subnet.production_endpoints[*].id
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = aws_vpc.production.id
  
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false
  
  tags = {
    Name = "ABSA-Production-TGW-Attachment"
  }
}

# TGW Route Table Association — Production uses prod_to_shared
resource "aws_ec2_transit_gateway_route_table_association" "production" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.production.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.production_to_shared.id
}

# TGW Route Propagation — Tell prod_to_shared about Production VPC CIDR
resource "aws_ec2_transit_gateway_route_table_propagation" "production" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.production.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.production_to_shared.id
}

# Route in Production VPC to reach other VPCs via TGW
resource "aws_route" "production_to_tgw" {
  for_each = {
    shared = var.vpc_cidrs.devops    # DevOps hosts shared tools
    staging = var.vpc_cidrs.staging   # Staging for testing
    # HR and Finance intentionally EXCLUDED from Production routing
  }
  
  route_table_id         = aws_route_table.production_app.id
  destination_cidr_block = each.value
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
}