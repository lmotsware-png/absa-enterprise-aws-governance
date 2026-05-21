# ============================================
# HR VPC - Human Resources Systems
# ============================================

resource "aws_vpc" "hr" {
  cidr_block                           = var.vpc_cidrs.hr
  instance_tenancy                     = "default"
  enable_dns_support                   = true
  enable_dns_hostnames                 = true
  enable_network_address_usage_metrics = true

  tags = merge(local.common_tags, {
    Name        = "ABSA-HR-VPC"
    Environment = "Production"
    DataClass   = "PII"
  })
}

resource "aws_internet_gateway" "hr" {
  vpc_id = aws_vpc.hr.id

  tags = { Name = "ABSA-HR-IGW" }
}

resource "aws_eip" "hr_nat" {
  count  = var.create_nat_gateways ? length(var.availability_zones) : 0
  domain = "vpc"

  tags = {
    Name = "ABSA-HR-NAT-EIP-${element(var.availability_zones, count.index)}"
  }
}

resource "aws_nat_gateway" "hr" {
  count         = var.create_nat_gateways ? length(var.availability_zones) : 0
  allocation_id = aws_eip.hr_nat[count.index].id
  subnet_id     = aws_subnet.hr_public[count.index].id

  tags = {
    Name = "ABSA-HR-NAT-${element(var.availability_zones, count.index)}"
  }

  depends_on = [aws_internet_gateway.hr]
}

resource "aws_subnet" "hr_public" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.hr.id
  cidr_block              = cidrsubnet(var.vpc_cidrs.hr, 8, count.index + local.tier_offsets.public.start)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "ABSA-HR-Public-${element(var.availability_zones, count.index)}"
    Tier = "Public"
  }
}

resource "aws_subnet" "hr_app" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.hr.id
  cidr_block        = cidrsubnet(var.vpc_cidrs.hr, 8, count.index + local.tier_offsets.app.start)
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "ABSA-HR-App-${element(var.availability_zones, count.index)}"
    Tier = "Application"
  }
}

resource "aws_subnet" "hr_data" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.hr.id
  cidr_block        = cidrsubnet(var.vpc_cidrs.hr, 8, count.index + local.tier_offsets.data.start)
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "ABSA-HR-Data-${element(var.availability_zones, count.index)}"
    Tier = "Data"
  }
}

resource "aws_subnet" "hr_endpoints" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.hr.id
  cidr_block        = cidrsubnet(var.vpc_cidrs.hr, 8, count.index + local.tier_offsets.endpoints.start)
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "ABSA-HR-Endpoints-${element(var.availability_zones, count.index)}"
    Tier = "VPC-Endpoints"
  }
}

resource "aws_route_table" "hr_public" {
  vpc_id = aws_vpc.hr.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.hr.id
  }

  tags = { Name = "ABSA-HR-Public-RT" }
}

resource "aws_route_table" "hr_app" {
  count  = length(var.availability_zones)
  vpc_id = aws_vpc.hr.id

  dynamic "route" {
    for_each = var.create_nat_gateways ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.hr[count.index].id
    }
  }

  tags = {
    Name = "ABSA-HR-App-RT-${element(var.availability_zones, count.index)}"
  }
}

resource "aws_route_table" "hr_data" {
  vpc_id = aws_vpc.hr.id

  tags = { Name = "ABSA-HR-Data-RT" }
}

resource "aws_route_table_association" "hr_public" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.hr_public[count.index].id
  route_table_id = aws_route_table.hr_public.id
}

resource "aws_route_table_association" "hr_app" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.hr_app[count.index].id
  route_table_id = aws_route_table.hr_app[count.index].id
}

resource "aws_route_table_association" "hr_data" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.hr_data[count.index].id
  route_table_id = aws_route_table.hr_data.id
}

resource "aws_ec2_transit_gateway_vpc_attachment" "hr" {
  subnet_ids         = aws_subnet.hr_endpoints[*].id
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = aws_vpc.hr.id

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = { Name = "ABSA-HR-TGW-Attachment" }
}

# HR shares the same TGW route table as Production for shared services access
resource "aws_ec2_transit_gateway_route_table_association" "hr" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hr.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.production_to_shared.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "hr" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hr.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.production_to_shared.id
}

resource "aws_route" "hr_to_shared_via_tgw" {
  for_each = {
    shared = var.vpc_cidrs.devops
  }

  route_table_id         = aws_route_table.hr_app[0].id
  destination_cidr_block = each.value
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
}

resource "aws_route" "hr_data_to_shared_via_tgw" {
  for_each = {
    shared = var.vpc_cidrs.devops
  }

  route_table_id         = aws_route_table.hr_data.id
  destination_cidr_block = each.value
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
}