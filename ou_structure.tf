# The hierarchy mirrors ABSA's business separation requirements:
#
# Root
# ├── Production OU      — Core banking workloads
# ├── Development OU     — Dev environments with resource limits
# ├── Staging OU         — Pre-production validation
# └── Shared Services OU — Logging, Audit, Security tooling

resource "aws_organizations_organizational_unit" "production" {
  name      = "Production"
  parent_id = aws_organizations_organization.absa.roots[0].id
}

resource "aws_organizations_organizational_unit" "development" {
  name      = "Development"
  parent_id = aws_organizations_organization.absa.roots[0].id
}

resource "aws_organizations_organizational_unit" "staging" {
  name      = "Staging"
  parent_id = aws_organizations_organization.absa.roots[0].id
}

resource "aws_organizations_organizational_unit" "shared_services" {
  name      = "Shared-Services"
  parent_id = aws_organizations_organization.absa.roots[0].id
}

# Nestled OUs for finer-grained control (optional but enterprise-ready)
resource "aws_organizations_organizational_unit" "production_hr" {
  name      = "HR-Systems"
  parent_id = aws_organizations_organizational_unit.production.id
}

resource "aws_organizations_organizational_unit" "production_finance" {
  name      = "Finance-Systems"
  parent_id = aws_organizations_organizational_unit.production.id
}