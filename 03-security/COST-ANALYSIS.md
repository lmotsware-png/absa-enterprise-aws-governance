

```markdown
# 🔐 Week 3 — Security Layer Cost Analysis

## Services Deployed

* IAM Roles (7 service-specific roles)
* KMS Keys (5 encryption keys with annual rotation)
* AWS Secrets Manager (3 secrets)
* Amazon GuardDuty (threat detection)
* AWS Security Hub (compliance dashboard)
* AWS WAF (Web Application Firewall)
* Lambda Functions (2 auto-remediation functions)
* SNS Topics (alerting)
* CloudWatch Logs (WAF logs)

---

# ⚠️ Major Cost Drivers

| Service             | Why It Costs                        |
| ------------------- | ----------------------------------- |
| GuardDuty           | Per-event analysis pricing          |
| Security Hub        | Per-check pricing across standards  |
| WAF                 | Per-ACL + per-rule pricing          |
| Secrets Manager     | Per-secret storage + API calls      |
| KMS                 | Per-key monthly charge              |

---

# 💵 Estimated Monthly Cost Breakdown

## IAM Roles

| Resource           | Quantity | Cost   |
| ------------------ | -------- | ------ |
| IAM Roles          | 7        | Free   |
| IAM Policies       | Multiple | Free   |
| Policy Attachments | Multiple | Free   |

### Notes

IAM is completely free. No cost regardless of usage volume.
However, poor IAM design can lead to security incidents
that have massive financial impact.

---

## KMS Keys

| Resource            | Quantity | Approx Cost     |
| ------------------- | -------- | --------------- |
| KMS Customer Keys   | 5        | ~$5.00/month    |
| Key Rotation        | Included | Free            |

### Notes

- $1 per key per month (prorated)
- Automatic rotation is free
- API calls (Encrypt/Decrypt/GenerateDataKey) cost extra:
  - ~$0.03 per 10,000 requests
  - For low-to-moderate usage: negligible (<$1/month)

---

## Secrets Manager

| Resource          | Quantity | Approx Cost     |
| ----------------- | -------- | --------------- |
| Secrets Stored    | 3        | ~$1.20/month    |
| API Calls         | Variable | ~$0.50/month    |

### Notes

- $0.40 per secret per month
- $0.05 per 10,000 API calls
- For banking app with moderate traffic:
  - Pods fetch secrets at startup (infrequent)
  - Rotation once every 30 days
  - Total API calls: negligible cost

---

## GuardDuty

| Resource                    | Estimated Cost    |
| --------------------------- | ----------------- |
| Threat Detection            | ~$1–$5/month      |
| CloudTrail Analysis         | Included          |
| VPC Flow Log Analysis       | Included          |
| DNS Log Analysis            | Included          |
| S3 Data Event Analysis      | Extra if enabled  |

### Notes

- Pricing based on volume of events analyzed
- For low-to-moderate lab usage: ~$2–$3/month
- Scales with account activity
- First 30 days free for new accounts
- Organization auto-enable: no extra cost

---

## Security Hub

| Resource                    | Estimated Cost    |
| --------------------------- | ----------------- |
| Foundational Best Practices | ~$1–$2/month      |
| CIS Benchmark               | ~$1–$3/month      |
| PCI-DSS                     | ~$1–$2/month      |
| Findings Aggregation        | Included          |

### Notes

- ~$0.001 per check per account per region
- 3 standards × ~200 checks total = ~600 checks
- For low-usage environment: ~$3–$7/month
- 30-day free trial for new accounts
- Consolidated findings across organization: no extra cost

---

## WAF

| Resource          | Quantity | Approx Cost     |
| ----------------- | -------- | --------------- |
| Web ACL           | 1        | ~$5.00/month    |
| Managed Rules     | 3        | ~$3.00/month    |
| Custom Rules      | 4        | ~$4.00/month    |
| Request Inspection| Variable | ~$1.00/month    |

### Notes

- $5 per ACL per month
- $1 per rule per month (managed rules from AWS)
- $1 per custom rule per month
- $0.60 per million requests inspected
- For low-traffic lab: ~$8–$13/month

---

## Lambda Remediation

| Resource              | Estimated Cost |
| --------------------- | -------------- |
| Block Public S3       | Free (<1M invocations/month) |
| Revoke Unused IAM     | Free (1 invocation/day = 30/month) |

### Notes

- Both functions well within AWS Free Tier:
  - 1 million free invocations per month
  - Block Public S3: triggers only on actual events (rare)
  - Revoke Unused IAM: once daily = 30 invocations/month
- Total: $0/month

---

## SNS Topics

| Resource          | Quantity | Cost   |
| ----------------- | -------- | ------ |
| SNS Topics        | 2        | Free   |
| Notifications     | Variable | ~$0    |

### Notes

- SNS topics are free
- First 1,000 email notifications free per month
- For low-usage lab: $0/month

---

## CloudWatch Logs (WAF)

| Resource              | Estimated Cost |
| --------------------- | -------------- |
| WAF Log Ingestion     | ~$0.50–$2/month|
| Log Storage (90 days) | ~$0.10–$0.50/month |

### Notes

- $0.50 per GB ingested
- $0.03 per GB stored
- WAF logs are relatively small
- For low-traffic lab: ~$1–$3/month

---

# 📊 Estimated Total Cost — Week 3

| Environment Type | Estimated Monthly Cost |
| ---------------- | ---------------------- |
| Lab / Low Usage  | ~$15–$25/month         |
| Moderate Testing | ~$30–$60/month         |
| Enterprise Scale | $100+/month            |

---

# 🧠 Week 3 Cost Optimization

## With Toggles OFF

If you set in `terraform.tfvars`:

```hcl
enable_guardduty    = false  # Save ~$3/month
enable_security_hub = false  # Save ~$5/month
enable_waf          = false  # Save ~$13/month
```

| Service              | Cost with Toggles OFF |
| -------------------- | --------------------- |
| KMS Keys             | ~$5.00/month          |
| Secrets Manager      | ~$1.70/month          |
| IAM Roles            | $0                    |
| Lambda               | $0                    |
| SNS                  | $0                    |
| **Total**            | **~$6.70/month**      |

### Notes

When practicing or learning:
- KMS keys exist but cost is minimal
- Secrets Manager retains secrets
- IAM roles provide zero-cost security structure
- Total security baseline: under $7/month

---

# 📈 Combined Cost Summary — All Weeks

| Week                   | Lab / Low Usage | Moderate Testing |
| ---------------------- | --------------- | ---------------- |
| Week 1 — Governance    | ~$0–$2/month    | ~$2–$5/month     |
| Week 2 — Networking    | ~$150–$250/month| ~$300–$500/month |
| Week 3 — Security      | ~$15–$25/month  | ~$30–$60/month   |
| **RUNNING TOTAL**      | **~$165–$277/month** | **~$332–$565/month** |

---

# ⚡ Cost Optimization Summary

## Immediate Cost Reduction Strategies

### For Practice/Learning:

| Action                              | Savings          |
| ----------------------------------- | ---------------- |
| Set `enable_guardduty = false`      | ~$3/month        |
| Set `enable_security_hub = false`   | ~$5/month        |
| Set `enable_waf = false`            | ~$13/month       |
| Set `create_nat_gateways = false`   | ~$100/month      |
| Set `create_vpc_endpoints = false`  | ~$50/month       |
| **Total potential savings**         | **~$171/month**  |

### Minimum Viable Cost (all toggles off):

| Resource              | Monthly Cost |
| --------------------- | ------------ |
| KMS Keys (5)          | ~$5.00       |
| Secrets Manager (3)   | ~$1.70       |
| Transit Gateway (1)   | ~$30–$50     |
| S3 State Bucket       | <$1          |
| DynamoDB Lock Table   | <$1          |
| IAM, SCPs, OUs        | $0           |
| **Total Minimum**     | **~$38–$59/month** |

### Notes

- The absolute minimum cost while keeping the architecture
  intact is around $40–$60/month
- This preserves the full governance, networking, and security
  structure while disabling the most expensive operational services
- Perfect for learning: deploy, study, and `terraform destroy`

---

# 🛡️ Financial Services Context

## Why These Costs Are Justified in Production

For a bank like ABSA:

| Security Capability         | Cost of NOT Having It                |
| --------------------------- | ------------------------------------ |
| GuardDuty                   | Undetected breach: millions in fines |
| Security Hub + PCI-DSS      | Failed audit: loss of banking license|
| WAF                         | SQL injection: customer data exposed |
| KMS encryption              | Data breach: POPIA/GDPR penalties    |
| Secrets Manager             | Hardcoded credentials: full system compromise |
| CloudTrail + SCP protection | No audit trail: regulatory violation |

### The Math:

```
Security infrastructure:        ~$200–$300/month
Average data breach cost:       ~$4.45 million (IBM 2024 report)
Regulatory fine (POPIA):        Up to R10 million (~$530,000)
Regulatory fine (GDPR):         Up to €20 million (~$21 million)

ROI of security investment:     Immeasurable
```

---

# 📌 Key Takeaways — Weeks 1–3

1. **Governance is free but critical** — SCPs and OUs cost nothing but
   provide the foundation for everything else

2. **Networking is the biggest cost driver** — NAT Gateways and VPC
   endpoints dominate the bill

3. **Security has a fixed baseline** — KMS and Secrets Manager create
   a minimum ~$7/month floor

4. **Toggles enable cost control** — Design your Terraform with
   boolean flags for expensive services

5. **Enterprise architecture costs money** — A proper multi-account
   Landing Zone costs $40–$60/month minimum, even idle

6. **Cost is proportional to security** — More secure = more expensive,
   but the cost of insecurity is orders of magnitude higher

---

**Last Updated:** May 2026
**Project:** ABSA Enterprise AWS Landing Zone
**Course:** AWS Solutions Architect Professional Preparation
```

---

## Where to Insert This

In your `COST-ANALYSIS.md` file:

1. Update the status table:
```markdown
| Week 3 — Security Layer        | ✅ Complete     |
```

2. Insert the entire Week 3 section after the Week 2 cost analysis

3. Update the Combined Cost Summary at the bottom with all three weeks

---

**Copy this into your `COST-ANALYSIS.md` file. Then we can push all Week 3 files to GitHub.**

