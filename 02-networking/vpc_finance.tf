# ============================================
# Finance VPC - PCI-DSS Regulated Workloads
# ============================================

resource "aws_vpc" "finance" {
  cidr_block                           = var.vpc_cidrs.finance
  instance_tenancy                     = "default"
  enable_dns_support                   = true
  enable_dns_hostnames                 = true
  enable_network_address_usage_metrics = true

  tags = merge(local.common_tags, {
    Name        = "ABSA-Finance-VPC"
    Environment = "Production"
    DataClass   = "PCI-DSS-Highly-Restricted"
  })
}

resource "aws_internet_gateway" "finance" {
  vpc_id = aws_vpc.finance.id

  tags = { Name = "ABSA-Finance-IGW" }
}

resource "aws_eip" "finance_nat" {
  count  = var.create_nat_gateways ? length(var.availability_zones) : 0
  domain = "vpc"

  tags = {
    Name = "ABSA-Finance-NAT-EIP-${element(var.availability_zones, count.index)}"
  }
}

resource "aws_nat_gateway" "finance" {
  count         = var.create_nat_gateways ? length(var.availability_zones) : 0
  allocation_id = aws_eip.finance_nat[count.index].id
  subnet_id     = aws_subnet.finance_public[count.index].id

  tags = {
    Name = "ABSA-Finance-NAT-${element(var.availability_zones, count.index)}"
  }

  depends_on = [aws_internet_gateway.finance]
}

resource "aws_subnet" "finance_public" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.finance.id
  cidr_block              = cidrsubnet(var.vpc_cidrs.finance, 8, count.index + local.tier_offsets.public.start)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "ABSA-Finance-Public-${element(var.availability_zones, count.index)}"
    Tier = "Public"
  }
}

resource "aws_subnet" "finance_app" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.finance.id
  cidr_block        = cidrsubnet(var.vpc_cidrs.finance, 8, count.index + local.tier_offsets.app.start)
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "ABSA-Finance-App-${element(var.availability_zones, count.index)}"
    Tier = "Application"
  }
}

resource "aws_subnet" "finance_data" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.finance.id
  cidr_block        = cidrsubnet(var.vpc_cidrs.finance, 8, count.index + local.tier_offsets.data.start)
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "ABSA-Finance-Data-${element(var.availability_zones, count.index)}"
    Tier = "Data"
  }
}

resource "aws_subnet" "finance_endpoints" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.finance.id
  cidr_block        = cidrsubnet(var.vpc_cidrs.finance, 8, count.index + local.tier_offsets.endpoints.start)
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "ABSA-Finance-Endpoints-${element(var.availability_zones, count.index)}"
    Tier = "VPC-Endpoints"
  }
}

resource "aws_route_table" "finance_public" {
  vpc_id = aws_vpc.finance.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.finance.id
  }

  tags = { Name = "ABSA-Finance-Public-RT" }
}

resource "aws_route_table" "finance_app" {
  count  = length(var.availability_zones)
  vpc_id = aws_vpc.finance.id

  dynamic "route" {
    for_each = var.create_nat_gateways ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.finance[count.index].id
    }
  }

  tags = {
    Name = "ABSA-Finance-App-RT-${element(var.availability_zones, count.index)}"
  }
}

resource "aws_route_table" "finance_data" {
  vpc_id = aws_vpc.finance.id

  tags = { Name = "ABSA-Finance-Data-RT" }
}

resource "aws_route_table_association" "finance_public" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.finance_public[count.index].id
  route_table_id = aws_route_table.finance_public.id
}

resource "aws_route_table_association" "finance_app" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.finance_app[count.index].id
  route_table_id = aws_route_table.finance_app[count.index].id
}

resource "aws_route_table_association" "finance_data" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.finance_data[count.index].id
  route_table_id = aws_route_table.finance_data.id
}

resource "aws_ec2_transit_gateway_vpc_attachment" "finance" {
  subnet_ids         = aws_subnet.finance_endpoints[*].id
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = aws_vpc.finance.id

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = { Name = "ABSA-Finance-TGW-Attachment" }
}

# Finance gets its OWN isolated TGW route table
resource "aws_ec2_transit_gateway_route_table_association" "finance" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.finance.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.finance_to_shared.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "finance" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.finance.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.finance_to_shared.id
}

# Finance can ONLY reach Shared Services
resource "aws_route" "finance_to_shared_via_tgw" {
  for_each = {
    shared = var.vpc_cidrs.devops
  }

  route_table_id         = aws_route_table.finance_app[0].id
  destination_cidr_block = each.value
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
}

resource "aws_route" "finance_data_to_shared_via_tgw" {
  for_each = {
    shared = var.vpc_cidrs.devops
  }

  route_table_id         = aws_route_table.finance_data.id
  destination_cidr_block = each.value
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
}