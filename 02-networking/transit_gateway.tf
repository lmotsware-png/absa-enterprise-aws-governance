# ============================================
# TRANSIT GATEWAY — Central Routing Hub
# ============================================

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

# ============================================
# TGW ROUTE TABLES — All Created via for_each
# ============================================
# ONE BLOCK creates ALL route tables from locals.tgw_route_table_names.
# 
# Previously, production_to_shared, shared_to_production, and staging_to_shared
# were defined as INDIVIDUAL resources. This created DUPLICATES because
# the for_each resource also created them.
#
# FIX: Remove all individual route table resources. Keep ONLY this for_each
# resource. All route table names are now defined in locals.tf.
#
# Add a new route table: add ONE line to locals.tgw_route_table_names.
# No new resource block needed.
# ============================================

resource "aws_ec2_transit_gateway_route_table" "segments" {
  for_each = local.tgw_route_table_names

  transit_gateway_id = aws_ec2_transit_gateway.main.id

  tags = merge(local.common_tags, {
    Name = each.value          # e.g. "production-to-shared-services"
    Type = "Segmented-Routing"
  })
}

# ============================================
# OPTIONAL — Future Route Tables
# ============================================
# To add a new route table for HR VPC:
# 1. Add to locals.tgw_route_table_names:
#    hr_to_shared = "hr-to-shared-services"
# 2. Terraform automatically creates:
#    aws_ec2_transit_gateway_route_table.segments["hr_to_shared"]
# 3. Reference it as:
#    aws_ec2_transit_gateway_route_table.segments["hr_to_shared"].id
# ============================================
