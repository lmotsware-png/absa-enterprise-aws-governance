![AWS Certified](https://img.shields.io/badge/AWS-Certified%20Solutions%20Architect%20Associate-orange)

# ABSA Enterprise AWS - Governance Layer (Week 1)

[![Terraform](https://img.shields.io/badge/terraform-1.5+-blue)](https://www.terraform.io)
[![AWS](https://img.shields.io/badge/AWS-Organizations-orange)](https://aws.amazon.com/organizations/)
[![Deployed](https://img.shields.io/badge/deployed-May%202026-green)](https://github.com/lmotsware-png/absa-enterprise-aws-governance)
[![SCPs](https://img.shields.io/badge/SCPs-4-red)](https://aws.amazon.com/organizations/scp/)

## 🏦 Project Overview

This is **Week 1 of a 6-week enterprise AWS Landing Zone deployment** for a fictional ABSA banking environment. This Terraform configuration establishes the foundation of AWS Organizations with proper governance, security controls, and multi-account strategy.

**✅ Tested and deployed to live AWS environment on May 14, 2026**

## ⚠️ CRITICAL: Before You Deploy — Read This First

This code was **tested and deployed to a live AWS environment on May 14, 2026**. The deployment was successful.

### 1. Email Addresses — The Most Important Thing

The emails in this configuration (`@absa.co.za`) are **demonstration examples** modeled after a fictional ABSA bank scenario. I do not control the `absa.co.za` domain.

**YOU MUST CHANGE THESE EMAILS** to ones you personally control before deploying.

If you deploy with emails you don't control:
- You **cannot** recover root user access to the member accounts
- You **cannot** sign in to add a payment method
- You **cannot** leave the AWS Organization from those accounts
- You **will** need AWS Support to manually intervene (takes hours)
- The accounts become **stuck** in your organization for 90 days

**✅ Do this instead:**
```hcl
# Use Gmail plus addressing or your own domain
log_archive_email = "yourname+log@gmail.com"
audit_email       = "yourname+audit@gmail.com"
