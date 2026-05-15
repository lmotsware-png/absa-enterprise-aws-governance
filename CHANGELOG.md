# Changelog

All notable changes to this project will be documented here.

## [1.0.0] - 2026-05-14

### Added - Initial Release

- AWS Organizations with 5 Organizational Units (OUs)
  - Production OU
  - Development OU  
  - Staging OU
  - Shared Services OU
  - Security OU

- 8 Member Accounts Created
  - production-applications
  - production-data
  - development-applications
  - development-sandbox
  - staging-applications
  - shared-network
  - shared-security-audit
  - shared-logging

- 4 Service Control Policies (SCPs)
  - Prevent-CloudTrail-Deletion (Root level)
  - Production-Security-Controls (Production OU)
  - Development-Instance-Limits (Development OU)
  - Prevent-Leave-Organization (Root level)

### Security

- Encryption enforced on all S3 buckets
- Public S3 access denied at organization level
- Production restricted to EU regions only
- CloudTrail deletion prevented

### Documentation

- Complete README with deployment instructions
- Security policy added
- Testing methodology documented

---

## [Upcoming]

### Week 2 - Networking Layer
- Transit Gateway setup
- VPCs per account
- VPC Endpoints

### Week 3 - Security Layer
- GuardDuty enablement
- Security Hub configuration
- Lambda auto-remediation
