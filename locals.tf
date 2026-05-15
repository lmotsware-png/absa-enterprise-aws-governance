locals {
  # OUs in ABSA's structure
  all_ous = {
    production     = aws_organizations_organizational_unit.production
    development    = aws_organizations_organizational_unit.development
    staging        = aws_organizations_organizational_unit.staging
    shared_services = aws_organizations_organizational_unit.shared_services
  }

  # Tag policies enforced organization-wide
  required_tags = ["Owner", "Environment", "CostCenter"]

  # This map feeds the Control Tower controlled OUs
  controlled_ous = {
    "Production"      = aws_organizations_organizational_unit.production.id
    "Development"     = aws_organizations_organizational_unit.development.id
    "Staging"         = aws_organizations_organizational_unit.staging.id
    "Shared-Services"  = aws_organizations_organizational_unit.shared_services.id
  }
}