# ABSA Enterprise AWS Landing Zone
## A Production-Grade Cloud Architecture Project

**Author:** Lerato Motsware  
**Timeline:** One enterprise layer per week  
**Stack:** AWS · Terraform · Python · Infrastructure as Code  
**Status:** Week 1–3 Complete · Week 4 In Progress

---

## Project Overview

This project designs and deploys a complete enterprise AWS cloud infrastructure for a simulated banking environment modelled on ABSA — one of Africa's largest financial institutions. Every architectural decision is driven by real-world enterprise requirements: PCI-DSS compliance, network segmentation, encryption at rest and in transit, automated threat detection, and zero-trust networking.

The entire environment is built as Infrastructure as Code using Terraform, applying production-grade patterns throughout: `for_each` over explicit repetition, locals-driven metadata, remote state coordination between stacks, and dynamic blocks over hardcoded configuration. No manual console clicks. No hardcoded values. No copy-paste resource blocks.

---

## Architecture Summary

```
Week 1  →  Governance        AWS Organizations · SCPs · Multi-account · CloudTrail
Week 2  →  Networking        6 VPCs · Transit Gateway · VPC Endpoints · Subnets
Week 3  →  Security          IAM · KMS · Secrets Manager · GuardDuty · WAF · Lambda
Week 4  →  Production        EKS · CloudFront · ALB · RDS · ElastiCache · CI/CD
```

---

## Week 1 — Governance and Multi-Account Architecture

### What Was Built

The foundation of the entire platform: an AWS Organisation with isolated accounts for every business unit, governed by Service Control Policies that nobody — not even an administrator — can bypass.

```
Management Account
├── Production OU
│     └── Production Account      (core banking workloads)
├── Finance OU
│     └── Finance Account         (regulatory reporting)
├── HR OU
│     └── HR Account              (employee systems)
├── DevOps OU
│     └── DevOps Account          (CI/CD, tooling)
└── Non-Production OU
      ├── Staging Account         (pre-production)
      └── QA Account              (quality assurance)
```

### Service Control Policies (Federal Laws)

SCPs are applied at the Organisational Unit level. Even an account root user cannot bypass them.

| SCP | What It Prevents |
|-----|-----------------|
| SCP-01 | Deleting or disabling CloudTrail in any account |
| SCP-02 | Disabling GuardDuty or Security Hub |
| SCP-03 | Creating public S3 buckets in Production OU |
| SCP-04 | Launching expensive EC2 instances in Non-Production |

### Remote State Architecture

Each week writes its outputs to a dedicated S3 state file. Each subsequent week reads the previous week's outputs via `terraform_remote_state`:

```
01-governance/terraform.tfstate  →  read by Week 2 and Week 3
02-networking/terraform.tfstate  →  read by Week 3 and Week 4
03-security/terraform.tfstate    →  read by Week 4
```

State stored in S3. Locked by DynamoDB. Encrypted at rest. Every infrastructure change is traceable.

---

## Week 2 — Multi-VPC Networking Architecture

### What Was Built

Six VPCs connected through a central Transit Gateway, each with four isolated subnet tiers. Network segmentation enforced entirely through routing — no firewall required.

### VPC Design

| VPC | CIDR | Purpose |
|-----|------|---------|
| Production | 10.1.0.0/16 | Core banking workloads |
| HR | 10.2.0.0/16 | Human resources systems |
| Finance | 10.3.0.0/16 | Financial reporting |
| DevOps | 10.4.0.0/16 | CI/CD and tooling |
| Staging | 10.5.0.0/16 | Pre-production testing |
| QA | 10.6.0.0/16 | Quality assurance |

### Four Subnet Tiers Per VPC (× 3 Availability Zones = 12 subnets each)

```
Public Subnets    10.x.1-3.0/24    ALB · NAT Gateway · Bastion
App Subnets       10.x.11-13.0/24  EKS Nodes · EC2 · Lambda
Data Subnets      10.x.21-23.0/24  RDS · ElastiCache  (NO internet route)
Endpoint Subnets  10.x.31-33.0/24  TGW ENIs · VPC Interface Endpoints
```

Subnet CIDRs are generated dynamically using `cidrsubnet()` driven by a locals metadata map — no hardcoded IP ranges anywhere in the codebase.

### Transit Gateway Segmentation

The Transit Gateway acts as the central router connecting all six VPCs. Route tables are manually controlled — no automatic propagation. This enforces business separation at the network layer:

```
Production   →  Shared Services  ✅
Finance      →  Shared Services  ✅
HR           →  Shared Services  ✅
DevOps       →  Shared Services  ✅
Staging      →  Shared Services  ✅

Production   →  HR               ❌  (no route exists)
Production   →  Finance          ❌  (no route exists)
Dev/Staging  →  Production       ❌  (no route exists)
```

No firewall needed. No ACL to maintain. The routing architecture **is** the security boundary.

### VPC Endpoints — Private AWS Service Access

All traffic to AWS services stays on the AWS private backbone. Zero bytes leave the network for CloudWatch, S3, ECR, Secrets Manager, KMS, STS, SQS, SNS, or Kinesis.

| Endpoint | Type | VPCs |
|----------|------|------|
| S3 Gateway | Gateway (free) | All 6 |
| CloudWatch Logs | Interface | All 6 |
| KMS | Interface | All 6 |
| ECR API + DKR | Interface | Production · DevOps · Staging |
| Secrets Manager | Interface | Production · Finance |
| STS | Interface | Production · DevOps |
| SQS + SNS | Interface | Production |
| Kinesis Streams + Firehose | Interface | Production · Finance |

### Transit Gateway Shared via AWS RAM

The Transit Gateway is created once in the network account and shared across the entire AWS Organisation using AWS Resource Access Manager. Every new account that joins inherits access automatically — zero operational overhead.

---

## Week 3 — Security Architecture

### What Was Built

Seven IAM roles with least-privilege policies, five independent KMS keys for encryption isolation, three Secrets Manager secrets with Terraform-generated passwords, GuardDuty across all accounts, Security Hub with three compliance frameworks, a seven-rule WAF Web ACL, and two Lambda auto-remediation functions.

---

### IAM Roles — Least Privilege Identity

| Role | Principal | Purpose |
|------|-----------|---------|
| ABSA-EKS-Cluster-Role | eks.amazonaws.com | EKS control plane manages AWS resources |
| ABSA-EKS-Node-Role | ec2.amazonaws.com | Worker nodes join cluster, pull images, assign pod IPs |
| ABSA-Lambda-Execution-Role | lambda.amazonaws.com | Lambda function execution |
| ABSA-Config-Role | config.amazonaws.com | AWS Config reads and audits all resources |
| ABSA-CloudTrail-Role | cloudtrail.amazonaws.com | CloudTrail writes encrypted logs |
| ABSA-Remediation-Role | lambda.amazonaws.com | Auto-remediation functions fix security issues |

Every role uses `sts:AssumeRole` with a scoped trust policy. Temporary credentials only. No permanent access keys anywhere.

---

### KMS Keys — Encryption at Rest (Isolated Blast Radius)

Five separate keys ensure that compromising one encryption key never exposes data protected by another.

| Key Alias | Protects | Key Policy |
|-----------|----------|------------|
| absa-rds-encryption | Aurora PostgreSQL | rds.amazonaws.com — 5 actions |
| absa-s3-encryption | S3 objects | s3.amazonaws.com — 5 actions |
| absa-secrets-encryption | Secrets Manager | secretsmanager.amazonaws.com — 3 actions |
| absa-lambda-encryption | Lambda env vars | lambda.amazonaws.com — 2 actions |
| absa-cloudtrail-encryption | CloudTrail logs | cloudtrail.amazonaws.com — 2 actions + condition |

All keys: 30-day deletion window · Annual automatic rotation · Account root emergency access · Customer managed (full audit visibility in CloudTrail).

The CloudTrail key uses an encryption context condition — the most restrictive key policy in the project. It only permits decryption when the caller can prove the request originates from a CloudTrail trail belonging to this specific AWS account.

---

### Secrets Manager — Zero Hardcoded Credentials

Three secrets, each with an independently generated 32-character password. No credential reuse. Compromise one — only one is exposed.

```
absa/api-gateway/client-secret
  client_id:     "absa-mobile-app"
  client_secret: <Terraform random_password — 32 chars — 95^32 combinations>
  environment:   "production"

absa/rds/master-password
  username: "absa_admin"
  password: <Terraform random_password — 32 chars>
  host:     absa-rds-cluster.cluster-xxx.eu-west-1.rds.amazonaws.com
  port:     5432
  engine:   aurora-postgresql

absa/elasticache/redis-auth-token
  auth_token:  <Terraform random_password — 32 chars>
  redis_host:  absa-redis-cluster.abcdefg.cache.amazonaws.com
  redis_port:  6379
```

All three secrets: encrypted by absa-secrets-encryption KMS key · 7-day recovery window · private access only via Secrets Manager VPC endpoint (Week 2).

---

### GuardDuty — Intelligent Threat Detection

- Analyses CloudTrail logs (API call anomalies)
- Analyses VPC Flow Logs (network anomalies)
- Analyses DNS logs (domain reputation)
- Analyses EKS audit logs (Kubernetes anomalies)
- Organisation admin account: all findings centralised from all 6 accounts
- Auto-enabled for new accounts: zero governance gaps

Findings route to CloudWatch EventBridge → SNS topic → security team within 15 minutes of detection.

---

### Security Hub — Compliance Dashboard

Three compliance frameworks evaluated continuously against the entire AWS estate:

| Standard | Controls | Purpose |
|----------|----------|---------|
| AWS Foundational Security Best Practices | 200+ | Deep AWS-specific technical controls |
| CIS AWS Foundations Benchmark v1.4.0 | 49 | Internationally recognised independent standard |
| PCI-DSS v3.2.1 | 62 | Payment card industry legal requirement |

Three custom Security Hub Insights surface the most critical issues immediately:

- **ABSA-Critical-Findings** — all CRITICAL severity active unresolved findings, grouped by severity
- **ABSA-Public-S3-Buckets** — all S3 compliance failures, grouped by resource ID
- **ABSA-Encryption-Issues** — all encryption compliance failures, grouped by resource type

---

### WAF Web ACL — Perimeter Defence at CloudFront Edge

Seven rules evaluated in priority order before any request reaches the ALB or VPC:

| Priority | Rule | Type | Action |
|----------|------|------|--------|
| 1 | SQL Injection Protection | AWS Managed | Block |
| 2 | Cross-Site Scripting Protection | AWS Managed | Block |
| 3 | IP Reputation | AWS Managed | Block |
| 4 | Rate Limiting (2000 req / 5 min / IP) | Custom | Block |
| 5 | User-Agent Validation (requires "ABSA-Mobile") | Custom | Block + custom 403 |
| 6 | Geo-Restriction (ZA, NA, BW, SZ, LS, GB) | Custom | Block + custom 403 |
| 7 | Request Size Limit (8KB max body) | Custom | Block |

WAF scope: `CLOUDFRONT` — attacks blocked at the edge, closest to the attacker. Blocked traffic never reaches eu-west-1. The WAF ACL ARN is exported via `outputs.tf` and will be consumed by Week 4's CloudFront distribution via `terraform_remote_state`.

All WAF events logged to CloudWatch Log Group with 90-day retention (PCI-DSS requirement). CloudWatch metrics enabled per rule for dashboards and alarms.

---

### Lambda Auto-Remediation — Closing the Security Loop

Two Lambda functions reduce mean time to remediation from 15–30 minutes (human response) to under 5 seconds (automated response).

**Function 1: ABSA-Block-Public-S3**

Trigger: EventBridge pattern — CloudTrail `PutBucketAcl` event where the ACL grants `AllUsers` or `AuthenticatedUsers`.

```python
s3.put_public_access_block(
    Bucket=bucket_name,
    PublicAccessBlockConfiguration={
        'BlockPublicAcls':       True,
        'IgnorePublicAcls':      True,
        'BlockPublicPolicy':     True,
        'RestrictPublicBuckets': True
    }
)
```

Exposure window with automation: < 1 second.  
Exposure window without automation: 15–30 minutes (human response).

**Function 2: ABSA-Revoke-Unused-IAM**

Trigger: EventBridge daily schedule (`rate(1 day)`).

Scans every IAM access key across all users. Deactivates (not deletes — recoverable) any key unused for more than 90 days. Satisfies PCI-DSS Requirement 8: remove or disable inactive user accounts and credentials within 90 days.

Both functions: least-privilege inline IAM policy · environment variables for all configuration · SNS notification on every remediation action · CloudTrail audit trail of every fix.

---

## The Complete Transaction Flow

This is how all three weeks work together during a real banking transaction.

```
Customer: Sipho Dlamini, Sandton, Johannesburg
Action:   Transfer R5,000 via ABSA mobile app
Time:     10:23:41 SAST
Result:   Payment successful ✅ in 360 milliseconds
```

### The Request Journey

```
Sipho's phone
    ↓ HTTPS (TLS 1.3)
CloudFront — Johannesburg edge PoP
    ↓ 7 WAF rules evaluated (< 1ms)
ALB — Public subnet 10.1.1.0/24
    ↓ Route to healthy pod
EKS payment-api pod — App subnet 10.1.11.45
    ↓ Credentials from Secrets Manager (private)
    ↓ Session check via Redis (10.1.21.20)
    ↓ Fraud check via SNS → SQS → fraud pod
RDS Aurora — Data subnet 10.1.21.15
    ↓ Transaction committed, encrypted by KMS
Redis — Data subnet 10.1.21.20
    ↓ Balance cache updated
SNS notifications — SMS to Sipho and recipient
```

### Every Approval Gate in This Transaction

| Action | Approved By | Mechanism |
|--------|-------------|-----------|
| Node assumes IAM role | STS validates trust policy | ec2.amazonaws.com in assume_role_policy |
| Node joins EKS cluster | AmazonEKSWorkerNodePolicy | policy attachment on node role |
| Pod gets VPC IP | AmazonEKS_CNI_Policy | policy attachment on node role |
| Pod pulls ECR image | AmazonEC2ContainerRegistryReadOnly | policy attachment on node role |
| Pod reads API secret | secretsmanager:GetSecretValue on absa/* | IAM policy on node role |
| Secrets Manager decrypts | kms:Decrypt on absa-secrets-encryption | KMS key policy |
| RDS writes encrypted data | kms:GenerateDataKey on absa-rds-encryption | KMS key policy |
| EKS creates ALB | AmazonEKSClusterPolicy on cluster role | policy attachment on cluster role |
| CloudTrail logs everything | SCP prevents deletion | Week 1 governance |
| GuardDuty monitors | Auto-enabled organisation-wide | Week 3 org configuration |
| WAF inspects request | 7 rules at CloudFront edge | Week 3 WAF ACL |

### Network Path — Zero Internet Exposure

Every internal AWS service call stays on the AWS private backbone:

```
STS credential exchange      →  STS endpoint ENI (10.1.31.5)
Secrets Manager reads        →  Secrets Manager ENI (10.1.31.6)
KMS decryption               →  KMS endpoint ENI (10.1.31.7)
ECR image pull               →  ECR API ENI (10.1.31.8) + ECR DKR ENI (10.1.31.9)
CloudWatch log writes        →  CloudWatch Logs ENI (10.1.31.10)
SNS notifications            →  SNS endpoint ENI (10.1.31.11)
SQS fraud queue reads        →  SQS endpoint ENI (10.1.31.12)
Kinesis fraud scoring        →  Kinesis ENI (10.1.31.13)
```

Zero bytes of internal traffic traverse the public internet.

---

## Defense in Depth — 8 Security Layers

```
Layer 1  SCPs prevent disabling security services              Week 1
Layer 2  IAM roles enforce least privilege at every step       Week 3
Layer 3  KMS encrypts all data at rest (5 separate keys)       Week 3
Layer 4  VPC endpoints keep all AWS service traffic private    Week 2
Layer 5  Private subnets with no internet routes (data tier)   Week 2
Layer 6  WAF blocks attacks at CloudFront edge (7 rules)       Week 3
Layer 7  GuardDuty detects anomalies in real time              Week 3
Layer 8  Lambda auto-remediates security issues in seconds     Week 3
```

An attacker must bypass every single layer. Bypassing any one layer is not enough.

---

## Infrastructure By the Numbers

| Category | Count |
|----------|-------|
| Terraform files | 24 (Weeks 1–3) |
| Architectural layers | 3 |
| AWS accounts | 7 |
| VPCs | 6 |
| Subnets | 72 |
| NAT Gateways | 18 |
| VPC Endpoints | 50+ |
| TGW Route Tables | 5 |
| IAM Roles | 7 |
| KMS Keys | 5 |
| Secrets | 3 |
| WAF Rules | 7 |
| Lambda Functions | 2 |
| Compliance Controls | 100+ |
| Security Layers | 8 |
| Approval gates per transaction | 12 |
| Transaction time | 360ms |

---

## Compliance Coverage

| Standard | Requirement | How It Is Met |
|----------|-------------|---------------|
| PCI-DSS Req 1 | Network segmentation | TGW route tables, private subnets, security groups |
| PCI-DSS Req 3 | Encrypt stored card data | KMS with customer managed keys on RDS and S3 |
| PCI-DSS Req 4 | Encrypt data in transit | TLS 1.3, VPC endpoints, no public internet paths |
| PCI-DSS Req 7 | Restrict access by need | IAM least-privilege roles, Secrets Manager scoping |
| PCI-DSS Req 8 | Identity and authentication | STS temporary credentials, 90-day key rotation |
| PCI-DSS Req 10 | Log and monitor all access | CloudTrail (immutable), GuardDuty, Security Hub |
| PCI-DSS Req 11 | Regularly test security | GuardDuty, Config, Security Hub automated checks |
| CIS 1.x | IAM hardening | No root access keys, MFA enforced via SCP |
| CIS 3.x | Logging | CloudTrail multi-region, encrypted, validated |
| CIS 5.x | Networking | No 0.0.0.0/0 on sensitive ports, flow logs enabled |

---

## Key Engineering Decisions

**Why `for_each` everywhere instead of `count`**  
`for_each` creates named resources keyed by map values rather than positional integers. Adding or removing a resource in the middle of a list with `count` causes Terraform to destroy and recreate everything after it. `for_each` is immune to this — each resource is independently addressable by its key.

**Why separate KMS keys per service**  
Five keys instead of one means each service has an independent blast radius. Compromising the RDS key does not expose S3 data, CloudTrail logs, or Lambda environment variables. The cost of five keys (five × $1/month) is trivial compared to the security value.

**Why `not_statement` in WAF rules 5 and 6**  
The action on these rules is `block`. To block everything that does NOT match a condition (legitimate ABSA clients, approved countries), you wrap the matching condition in `not_statement`. This is more precise than trying to enumerate all blocked patterns — you define what is allowed and block everything else.

**Why `endpoint subnets` as a separate tier**  
Interface endpoint ENIs and TGW attachments consume IP addresses from the subnets they are placed in. Placing them in a dedicated tier keeps infrastructure traffic physically separated from application traffic, prevents IP exhaustion in app subnets, and makes network flow analysis cleaner.

**Why Inactive instead of Delete for unused IAM keys**  
Auto-remediation should be reversible. Deactivating a key preserves it for recovery if the remediation was triggered incorrectly (e.g. a key used only by a monthly batch job). A human makes the final decision to delete permanently.

---

## What Is Coming in Week 4

- EKS cluster deployment with managed node groups
- CloudFront distribution consuming Week 3 WAF ACL via `terraform_remote_state`
- Application Load Balancer with SSL certificate (ACM)
- Aurora PostgreSQL cluster in data subnets
- ElastiCache Redis cluster in data subnets
- CI/CD pipeline with CodePipeline and CodeBuild
- Disaster Recovery region (af-south-1 — Cape Town)

---

## Repository

GitHub: [github.com/lmotsware-png/terraform-projects](https://github.com/lmotsware-png/terraform-projects)

---

*Built by Lerato Motsware — Electrical Engineer → Telecoms Technician → Network Engineer (CCNA) → Cloud Engineer*  
*From N3 to enterprise AWS architecture. One week at a time.*
