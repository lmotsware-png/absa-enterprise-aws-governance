# Transit Gateway — Central routing hub for all VPCs
resource "aws_ec2_transit_gateway" "main" {
  description                     = "ABSA Enterprise Transit Gateway - Central Hub"
  amazon_side_asn                 = var.transit_gateway.amazon_side_asn
  auto_accept_shared_attachments  = var.transit_gateway.auto_accept_shared_attachments
  default_route_table_association = var.transit_gateway.default_route_table_association
  default_route_table_propagation = var.transit_gateway.default_route_table_propagation
  dns_support                     = var.transit_gateway.dns_support
  vpn_ecmp_support                = var.transit_gateway.vpn_ecmp_support

  tags = merge(local.common_tags, {
    Name = "ABSA-TGW-Main"
  })
}

# TGW Route Table: Production → Shared Services
resource "aws_ec2_transit_gateway_route_table" "production_to_shared" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  
  tags = merge(local.common_tags, {
    Name = "production-to-shared-services"
    Type = "Segmented-Routing"
  })
}

# TGW Route Table: Shared Services → Production (restricted)
resource "aws_ec2_transit_gateway_route_table" "shared_to_production" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  
  tags = merge(local.common_tags, {
    Name = "shared-services-to-production"
    Type = "Segmented-Routing"
  })
}

# TGW Route Table: Development → Shared Services
resource "aws_ec2_transit_gateway_route_table" "segments" {
  for_each = local.tgw_route_table_names


  transit_gateway_id = aws_ec2_transit_gateway.main.id

  tags = merge(local.common_tags, {
    Name = each.value          # e.g. "production-to-shared-services"
    Type = "Segmented-Routing"
  })
}
# TGW Route Table: Staging → Shared Services
resource "aws_ec2_transit_gateway_route_table" "staging_to_shared" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  
  tags = merge(local.common_tags, {
    Name = "staging-to-shared-services"
    Type = "Segmented-Routing"
  })
}