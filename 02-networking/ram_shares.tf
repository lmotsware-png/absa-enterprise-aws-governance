# ============================================
# AWS RAM - Share Transit Gateway Across Accounts
# ============================================

# Create a RAM resource share for the Transit Gateway
resource "aws_ram_resource_share" "tgw" {
  name                      = "ABSA-Transit-Gateway-Share"
  allow_external_principals = false  # Only accounts within the organization

  tags = merge(local.common_tags, {
    Name = "ABSA-TGW-Share"
  })
}

# Share the Transit Gateway itself
resource "aws_ram_resource_association" "tgw" {
  resource_arn       = aws_ec2_transit_gateway.main.arn
  resource_share_arn = aws_ram_resource_share.tgw.arn
}

# Share with the entire AWS Organization
resource "aws_ram_principal_association" "organization" {
  principal          = data.terraform_remote_state.governance.outputs.organization_arn
  resource_share_arn = aws_ram_resource_share.tgw.arn
}

# ============================================
# How This Works:
# ============================================
#
# 1. The Transit Gateway is created in the management account
#    (or a shared-services account)
#
# 2. AWS RAM shares the TGW with ALL accounts in the organization
#
# 3. Member accounts can then attach their VPCs to this shared TGW
#
# 4. Without RAM sharing, each account would need its own TGW
#    (expensive and defeats the purpose of a central hub)