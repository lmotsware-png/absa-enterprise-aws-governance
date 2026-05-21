locals {
  # Subnet CIDR tier offsets
  # Public: 1-3, App: 11-13, Data: 21-23, Endpoints: 31-33
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

  # TGW route table names
  tgw_route_table_names = {
    production_to_shared = "production-to-shared-services"
    shared_to_production = "shared-services-to-production"
    finance_to_shared    = "finance-to-shared-services"
    dev_to_shared        = "development-to-shared-services"
    staging_to_shared    = "staging-to-shared-services"
  }
}