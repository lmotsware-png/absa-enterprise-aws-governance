# Attach the CloudTrail protection SCP to EVERYTHING (root)
resource "aws_organizations_policy_attachment" "root_cloudtrail" {
  policy_id = aws_organizations_policy.deny_cloudtrail_deletion.id
  target_id = aws_organizations_organization.absa.roots[0].id
}

# Attach production restrictions to Production OU only
resource "aws_organizations_policy_attachment" "production" {
  policy_id = aws_organizations_policy.production_restrictions.id
  target_id = aws_organizations_organizational_unit.production.id
}

# Attach development limits to Development OU only
resource "aws_organizations_policy_attachment" "development" {
  policy_id = aws_organizations_policy.dev_instance_limits.id
  target_id = aws_organizations_organizational_unit.development.id
}