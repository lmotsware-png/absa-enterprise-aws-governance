locals {
  # Subnet CIDR tier offsets
  tier_offsets = {
    public    = { start = 1,  end = 3,  newbits = 8 }  # /16 + 8 = /24
    app       = { start = 11, end = 13, newbits = 8 }
    data      = { start = 21, end = 23, newbits = 8 }
    endpoints = { start = 31, end = 33, newbits = 8 }
  }

  # Common tags applied to all resources
  common_tags = {
    Project     = "ABSA-Enterprise-AWS"
    CostCenter  = "Cloud-Infrastructure"
    DataClass   = "Internal"
    ManagedBy   = "Terraform"
  }

  # ============================================
  # TGW ROUTE TABLE NAMES — ALL DEFINED HERE
  # ============================================
  # This map drives the for_each in transit_gateway.tf
  # Add a new route table: add one line here.
  # The route table is automatically created.
  # ============================================

  tgw_route_table_names = {
    production_to_shared = "production-to-shared-services"
    shared_to_production = "shared-services-to-production"
    finance_to_shared    = "finance-to-shared-services"
    dev_to_shared        = "development-to-shared-services"
    staging_to_shared    = "staging-to-shared-services"
    # Add more here when needed:
    # qa_to_shared       = "qa-to-shared-services"
    # hr_to_shared       = "hr-to-shared-services"
  }

  # All VPCs map for iteration
  all_vpcs = {
    production  = aws_vpc.production
    hr          = aws_vpc.hr
    finance     = aws_vpc.finance
    devops      = aws_vpc.devops
    staging     = aws_vpc.staging
    qa          = aws_vpc.qa
  }
}
