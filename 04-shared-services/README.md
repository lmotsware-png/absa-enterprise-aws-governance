# Week 4: Shared Services — ABSA Enterprise AWS Landing Zone

## Overview

This is **Week 4 of the ABSA Enterprise AWS Landing Zone**. With governance
(Week 1), networking (Week 2), and security (Week 3) established, Week 4
builds the **centralized operations layer** that monitors, logs, and audits
every account in the organization.

**In plain English:** We're building the security cameras, the black box
recorder, and the operations center. This is where the operations team sees
everything happening across all accounts. This is what auditors review.
This is how you prove compliance.

---

## What We Built

### 1. Organization CloudTrail

- **Single trail for ALL accounts** — Every API call in every account logged
- **Multi-region** — eu-west-1, eu-west-2, af-south-1
- **Global services** — IAM, CloudFront, Route 53 events included
- **KMS encrypted** — Using Week 3 CloudTrail encryption key
- **Log file validation** — Tamper-proof digest files
- **S3 lifecycle** — 90 days hot storage → Glacier → 7 years retention
- **CloudWatch integration** — Real-time log streaming

### 2. AWS Config

- **Continuous recording** — Every resource change tracked
- **4 compliance rules**:
  - Encrypted EBS volumes required
  - RDS encryption required
  - S3 public read prohibited
  - Unrestricted SSH prohibited
- **SNS alerts** — Failed compliance checks notify immediately
- **24-hour snapshots** — Full resource inventory daily

### 3. CloudWatch Dashboards

- **Production Overview** — EKS health, RDS connections, Redis CPU, API traffic
- **Security Overview** — GuardDuty findings, WAF blocks, CloudTrail API calls
- **Single pane of glass** — Operations team sees everything at a glance

### 4. VPC Flow Logs

- **Production VPC** — All traffic logged for network analysis
- **Finance VPC** — PCI-DSS requirement for payment network monitoring
- **S3 destination** — Centralized storage with lifecycle policies
- **Custom log format** — Full metadata for every packet

### 5. Cross-Account IAM Roles

- **Operations Role** — ReadOnly + CloudWatch access across accounts
- **Security Audit Role** — Full security visibility
- **Billing Role** — Cost and usage access for finance team

### 6. Centralized Log Archive

- **3 S3 buckets** — CloudTrail, Config, Flow Logs
- **Encryption enforced** — S3 bucket policies deny unencrypted uploads
- **Public access blocked** — All buckets private
- **Versioning enabled** — CloudTrail bucket versioned for audit integrity
- **Lifecycle policies** — Automatic transition to Glacier

---

## Files in This Module

| File | What It Contains |
|------|-----------------|
| `main.tf` | Provider config, remote state from Weeks 1-3 |
| `variables.tf` | Retention periods, toggles |
| `terraform.tfvars` | ABSA-specific values |
| `locals.tf` | Bucket names, role names, KMS key references |
| `cloudtrail_organization.tf` | Organization CloudTrail, S3, KMS, CloudWatch |
| `aws_config.tf` | Config recorder, delivery channel, 4 rules |
| `cloudwatch_dashboards.tf` | Production and security dashboards |
| `vpc_flow_logs.tf` | Flow Logs for Production and Finance VPCs |
| `s3_log_archive.tf` | Encryption enforcement policies |
| `cross_account_roles.tf` | Operations, security audit, billing roles |
| `outputs.tf` | Exports for operations and Week 6 |
| `README.md` | This file |

---

## How Week 4 Connects
