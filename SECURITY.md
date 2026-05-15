# Security Policy

## Reporting a Vulnerability

If you find a security issue, **DO NOT** open a public issue.

Email me directly: **lmotsware@gmail.com**

I will respond within 48 hours.

## Security Controls in This Project

| Control | What It Does |
|---------|---------------|
| Prevent CloudTrail Deletion | Logs cannot be erased |
| Enforce Encryption | All S3 data is encrypted |
| Restrict Regions | Production only in EU |
| Limit Instance Types | Dev can't run expensive instances |

## My Security Background

This project reflects security practices I learned while supporting **South African National Defence Force (SANDF)** critical infrastructure:
- No unauthorized changes
- Immutable audit logs
- Least privilege access
