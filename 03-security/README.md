# Week 3: Security Layer — ABSA Enterprise AWS Landing Zone

## Overview

This is **Week 3 of a 6-week project** to build a production-ready, multi-account
AWS Landing Zone for a fictional enterprise bank (ABSA). With governance (Week 1)
and networking (Week 2) established, Week 3 builds the **security foundation**:
identity, encryption, secrets, threat detection, and automatic remediation.

**In plain English:** We're building the locks, alarms, and security cameras.
Who can access what? How is data protected? What happens when someone tries
something malicious? This layer ensures that even if an attacker gets past the
network, they find nothing in plaintext and every move is detected.

---

## What We Built

### 1. IAM Roles — Least Privilege Access

We created 7 service-specific IAM roles. Each role grants ONLY the permissions
that service needs — nothing more.

| Role | Used By | Key Permissions |
|------|---------|----------------|
| `ABSA-EKS-Cluster-Role` | EKS control plane | Manage EC2, networking, load balancers |
| `ABSA-EKS-Node-Role` | EKS worker nodes | Pull images from ECR, write logs, read secrets |
| `ABSA-Lambda-Execution-Role` | Lambda functions | Write CloudWatch logs, modify S3 ACLs |
| `ABSA-Secrets-Manager-Role` | EC2, ECS, Lambda | Read secrets from Secrets Manager |
| `ABSA-CloudTrail-Role` | CloudTrail service | Write logs to S3, CloudWatch |
| `ABSA-Config-Role` | AWS Config | Record resource configurations |
| `ABSA-Remediation-Lambda-Role` | Auto-remediation | Block public S3, revoke unused IAM keys |

**Key concept: Trust Policy vs Permission Policy**
- **Trust Policy** (`assume_role_policy`): WHO can use this role
- **Permission Policy**: WHAT the role can do

Both must allow for an action to succeed.

### 2. KMS Keys — Encryption at Rest

We created 5 separate KMS keys for encryption isolation. One compromised key
does not expose everything.

| Key Alias | Encrypts | Used By |
|-----------|----------|---------|
| `alias/absa-rds-encryption` | RDS database tables, snapshots | RDS service |
| `alias/absa-s3-encryption` | S3 objects | S3 service |
| `alias/absa-secrets-encryption` | Secrets Manager values | Secrets Manager service |
| `alias/absa-lambda-encryption` | Lambda environment variables | Lambda service |
| `alias/absa-cloudtrail-encryption` | CloudTrail log files | CloudTrail service |

**Key features:**
- 30-day deletion window (maximum protection against accidental deletion)
- Automatic annual key rotation
- Service-specific key policies (RDS can use its key, but not the Secrets key)

### 3. Secrets Manager — Secure Credential Storage

We created 3 secrets, all encrypted with the dedicated Secrets KMS key:

| Secret | Contains | Used By |
|--------|----------|---------|
| `absa/rds/master-password` | Database username, password, host, port | EKS pods connecting to RDS |
| `absa/api-gateway/client-secret` | API client ID and secret | Mobile app authentication |
| `absa/elasticache/redis-auth-token` | Redis AUTH token, host, port | EKS pods connecting to Redis |

**Each secret has its own randomly generated password** — no credential reuse.

### 4. GuardDuty — Intelligent Threat Detection

GuardDuty continuously analyzes:
- CloudTrail logs (every API call)
- VPC Flow Logs (all network traffic)
- DNS logs (domain queries)

When it detects suspicious behavior, it generates findings that flow to
Security Hub and SNS for alerting.

### 5. Security Hub — Central Security Dashboard

Security Hub aggregates findings from GuardDuty, AWS Config, and IAM Access
Analyzer into a single dashboard. We enabled 3 compliance standards:

| Standard | What It Checks |
|----------|---------------|
| AWS Foundational Best Practices | CloudTrail enabled, root MFA, S3 public blocks |
| CIS AWS Foundations Benchmark | Password policy, unused credentials, VPC flow logs |
| PCI-DSS | Encryption at rest, network segmentation, access logging |

### 6. WAF — Web Application Firewall

7 rules protect the banking application at the edge:

| Priority | Rule | What It Blocks |
|----------|------|---------------|
| 1 | SQL Injection Protection | Malicious SQL in requests |
| 2 | XSS Protection | Cross-site scripting attempts |
| 3 | IP Reputation | Known malicious IP addresses |
| 4 | Rate Limiting | More than 2000 requests/5 min from one IP |
| 5 | User-Agent Validation | Requests without "ABSA-Mobile" header |
| 6 | Geo-Restriction | Traffic outside South Africa + UK |
| 7 | Size Restriction | Request bodies larger than 8KB |

### 7. Lambda Auto-Remediation — Automatic Security Fixes

| Function | Trigger | What It Does |
|----------|---------|--------------|
| `ABSA-Block-Public-S3` | CloudTrail detects `PutBucketAcl` with public grant | Immediately blocks all public access on the bucket |
| `ABSA-Revoke-Unused-IAM` | Daily schedule | Deactivates IAM access keys unused for 90+ days |

---

## Files in This Module

| File | What It Contains |
|------|-----------------|
| `main.tf` | Provider config, remote state, data sources from Weeks 1 & 2 |
| `variables.tf` | All configurable inputs with types and defaults |
| `terraform.tfvars` | ABSA-specific values and cost toggles |
| `locals.tf` | KMS aliases, IAM role names, secret definitions |
| `iam_roles.tf` | 7 IAM roles with trust and permission policies |
| `kms_keys.tf` | 5 KMS keys with aliases |
| `kms_policies.tf` | Key policies controlling who can use each key |
| `secrets_manager.tf` | 3 secrets with randomly generated passwords |
| `guardduty.tf` | Threat detection detector and organization config |
| `security_hub.tf` | Central dashboard with 3 compliance standards |
| `waf.tf` | Web ACL with 7 rules and logging |
| `lambda_remediation.tf` | 2 auto-remediation Lambda functions |
| `outputs.tf` | Exports for Week 4 (Production) consumption |
| `README.md` | This file — the complete guide to Week 3 |

---

## How Week 3 Connects to Other Weeks
