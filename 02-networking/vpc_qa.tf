# ============================================
# QA VPC - Quality Assurance & Testing
# ============================================

resource "aws_vpc" "qa" {
  cidr_block                           = var.vpc_cidrs.qa
  instance_tenancy                     = "default"
  enable_dns_support                   = true
  enable_dns_hostnames                 = true
  enable_network_address_usage_metrics = true

  tags = merge(local.common_tags, {
    Name        = "ABSA-QA-VPC"
    Environment = "Development"
    DataClass   = "Internal-Test"
  })
}

resource "aws_internet_gateway" "qa" {
  vpc_id = aws_vpc.qa.id

  tags = { Name = "ABSA-QA-IGW" }
}

resource "aws_eip" "qa_nat" {
  count  = var.create_nat_gateways ? length(var.availability_zones) : 0
  domain = "vpc"

  tags = {
    Name = "ABSA-QA-NAT-EIP-${element(var.availability_zones, count.index)}"
  }
}

resource "aws_nat_gateway" "qa" {
  count         = var.create_nat_gateways ? length(var.availability_zones) : 0
  allocation_id = aws_eip.qa_nat[count.index].id
  subnet_id     = aws_subnet.qa_public[count.index].id

  tags = {
    Name = "ABSA-QA-NAT-${element(var.availability_zones, count.index)}"
  }

  depends_on = [aws_internet_gateway.qa]
}

resource "aws_subnet" "qa_public" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.qa.id
  cidr_block              = cidrsubnet(var.vpc_cidrs.qa, 8, count.index + local.tier_offsets.public.start)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "ABSA-QA-Public-${element(var.availability_zones, count.index)}"
    Tier = "Public"
  }
}

resource "aws_subnet" "qa_app" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.qa.id
  cidr_block        = cidrsubnet(var.vpc_cidrs.qa, 8, count.index + local.tier_offsets.app.start)
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "ABSA-QA-App-${element(var.availability_zones, count.index)}"
    Tier = "Application"
  }
}

resource "aws_subnet" "qa_data" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.qa.id
  cidr_block        = cidrsubnet(var.vpc_cidrs.qa, 8, count.index + local.tier_offsets.data.start)
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "ABSA-QA-Data-${element(var.availability_zones, count.index)}"
    Tier = "Data"
  }
}

resource "aws_subnet" "qa_endpoints" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.qa.id
  cidr_block        = cidrsubnet(var.vpc_cidrs.qa, 8, count.index + local.tier_offsets.endpoints.start)
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "ABSA-QA-Endpoints-${element(var.availability_zones, count.index)}"
    Tier = "VPC-Endpoints"
  }
}

resource "aws_route_table" "qa_public" {
  vpc_id = aws_vpc.qa.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.qa.id
  }

  tags = { Name = "ABSA-QA-Public-RT" }
}

resource "aws_route_table" "qa_app" {
  count  = length(var.availability_zones)
  vpc_id = aws_vpc.qa.id

  dynamic "route" {
    for_each = var.create_nat_gateways ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.qa[count.index].id
    }
  }

  tags = {
    Name = "ABSA-QA-App-RT-${element(var.availability_zones, count.index)}"
  }
}

resource "aws_route_table" "qa_data" {
  vpc_id = aws_vpc.qa.id

  tags = { Name = "ABSA-QA-Data-RT" }
}

resource "aws_route_table_association" "qa_public" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.qa_public[count.index].id
  route_table_id = aws_route_table.qa_public.id
}

resource "aws_route_table_association" "qa_app" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.qa_app[count.index].id
  route_table_id = aws_route_table.qa_app[count.index].id
}

resource "aws_route_table_association" "qa_data" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.qa_data[count.index].id
  route_table_id = aws_route_table.qa_data.id
}

resource "aws_ec2_transit_gateway_vpc_attachment" "qa" {
  subnet_ids         = aws_subnet.qa_endpoints[*].id
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = aws_vpc.qa.id

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = { Name = "ABSA-QA-TGW-Attachment" }
}

# QA shares the dev_to_shared route table with other dev environments
resource "aws_ec2_transit_gateway_route_table_association" "qa" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.qa.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.dev_to_shared.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "qa" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.qa.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.dev_to_shared.id
}

# QA can only reach Shared Services
resource "aws_route" "qa_to_shared_via_tgw" {
  route_table_id         = aws_route_table.qa_app[0].id
  destination_cidr_block = var.vpc_cidrs.devops
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
}