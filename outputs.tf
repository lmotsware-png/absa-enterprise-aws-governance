output "organization_id" {
  value = aws_organizations_organization.absa.id
}

output "production_ou_id" {
  value = aws_organizations_organizational_unit.production.id
}

output "development_ou_id" {
  value = aws_organizations_organizational_unit.development.id
}

output "staging_ou_id" {
  value = aws_organizations_organizational_unit.staging.id
}

output "shared_services_ou_id" {
  value = aws_organizations_organizational_unit.shared_services.id
}

output "nested_ou_map" {
  value = {
    hr      = aws_organizations_organizational_unit.production_hr.id
    finance = aws_organizations_organizational_unit.production_finance.id
  }
}

output "scp_ids" {
  value = {
    deny_cloudtrail  = aws_organizations_policy.deny_cloudtrail_deletion.id
    production       = aws_organizations_policy.production_restrictions.id
    development      = aws_organizations_policy.dev_instance_limits.id
  }
}