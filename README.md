## 📺 Watch Me Build This on YouTube

I am teaching this project step by step on YouTube. Every video explains the code, architecture, and decisions behind each layer.

👉 **[Subscribe to LM Cloud Architect](https://www.youtube.com/@LMCloudArchitect)**

### Videos in this series:

| Week | Topic | Video Link |
|------|-------|------------|
| Week 1 | Introduction – What Happens When You Send Money? | [Watch](https://youtu.be/0hpqJVTZI0c) |
| Week 1 | Terraform AWS Governance Deep Dive – terraform {} block & Providers | [Watch](https://youtu.be/ni7jhxthB44) |
| Week 1 | The Provider – Terraform Talks to AWS | [Watch](https://youtu.be/LUHkYg9BNuQ) |
| Week 1 | AWS Organizations & Control Tower – Week 1 (Step 3 & 4) | [Watch](https://youtu.be/36lmmxstt-M) |
| Week 1 | Log Archive & Audit Accounts – Week 1 (Step 5) | [Watch](https://youtu.be/KBaOCiNsc7g) |
| Week 1 | Understanding Organizational Units (OUs) – Week 1 (OU_structure.tf) | [Watch](https://youtu.be/FdzG5iXaFZU) |
| Week 1 | OU Structure, Variables, Locals, Outputs & SCPs – Week 1 (Deep Dive) | [Watch](https://youtu.be/2WusbmWkwIc) |
| Week 1 | Locals.tf Explained – Terraform Building Blocks (Week 1) | [Watch](https://youtu.be/hkCbNirBKw0) |
| Week 1 | Outputs.tf Explained – Terraform Building Blocks (Week 1) | [Watch](https://youtu.be/swxU2rsQS1A) |
| Week 1 | SCPs Explained – DenyCloudTrailDeletion & data vs resource | [Watch](https://youtu.be/U4mRGycR7nE) |
| Week 1 | ProductionRestrictions SCP – AWS Service Control Policies (Week 1) | [Watch](https://youtu.be/Sm_FZuV6jSA) |
| Week 1 | SCP 3: DevInstanceLimits – Prevent Expensive EC2 Instances in Dev (Week 1) | [Watch](https://youtu.be/_UfupTkT8cg) |
| Week 1 | SCP Attachments – Connecting SCPs to OUs (Week 1) | [Watch](https://youtu.be/W4SOoIcL2IE) |
| Week 2 | Coming soon | – |
| Week 3 | Coming soon | – |
| Week 4 | Coming soon | – |
| Week 5 | Coming soon | – |
| Week 6 | Coming soon | – |

📂 **Full Week 1 Slides:** http://spoo.me/01-gov
---

# 🏦 FINANCIAL BANK ABSA Enterprise AWS Landing Zone

### Enterprise Multi-Account AWS Platform Architecture with Terraform

**AWS | Terraform | Enterprise Networking | Security | Governance | Infrastructure as Code**

![AWS](https://img.shields.io/badge/AWS-Enterprise_Ready-FF9900?style=for-the-badge\&logo=amazonaws)
![Terraform](https://img.shields.io/badge/Terraform-1.8+-623CE4?style=for-the-badge\&logo=terraform)
![Architecture](https://img.shields.io/badge/Architecture-Multi_Account-blue?style=for-the-badge)
![Status](https://img.shields.io/badge/Status-Week_2_Complete-2ea44f?style=for-the-badge)
![Security](https://img.shields.io/badge/Security-PCI_DSS_Aligned-success?style=for-the-badge)

---

# 📌 Project Overview

This project simulates a real-world enterprise AWS banking environment for a fictional ABSA financial organization.

The objective is to design and deploy a secure, scalable, multi-account AWS landing zone using Terraform while applying enterprise cloud architecture, networking, governance, and security principles.

This is not a basic certification lab.

The project focuses on how enterprise organizations actually build cloud infrastructure at scale.

---

# 🏗️ Enterprise Architecture Scope

```text
absa-enterprise-aws/
│
├── 01-governance/
│   AWS Organizations, OUs, SCPs
│
├── 02-networking/
│   Transit Gateway, Multi-VPC Architecture, Endpoints
│
├── 03-security/
│   IAM, KMS, GuardDuty, Security Hub
│
├── 04-shared-services/
│   CloudTrail, Config, Monitoring
│
├── 05-production/
│   EKS, RDS, Redis, API Gateway
│
├── 06-data-platform/
│   Kinesis, Redshift, Athena, OpenSearch
│
├── 07-messaging/
│   SQS, SNS, Amazon MQ
│
├── 08-disaster-recovery/
│   Cross-Region Warm Standby
│
└── 09-devops/
    CI/CD, ECR, CodePipeline, CodeBuild
```

---

# 🧠 Why This Project Exists

Most cloud labs focus on:

* launching EC2 instances
* basic AWS services
* passing certification exams

This project focuses on:

* enterprise cloud architecture
* infrastructure dependency design
* routing and segmentation
* security-first networking
* governance at scale
* private AWS connectivity
* Terraform automation patterns
* operational cloud engineering

The deeper I progressed into the project, the more I realized:

> Cloud architecture without networking knowledge becomes extremely limited.

Understanding:

* CIDR planning
* subnetting
* routing
* NAT architecture
* DNS
* TLS
* Transit Gateway propagation
* VPC endpoints
* private AWS backbone connectivity

became essential to understanding how enterprise AWS environments actually operate.

---

# 🌐 Enterprise Networking Architecture

## Multi-VPC Design

The environment is segmented into dedicated VPCs:

* Production VPC
* HR VPC
* Finance VPC
* DevOps VPC
* Staging VPC
* QA VPC

Each VPC contains:

* Public subnet tier
* Application subnet tier
* Data subnet tier
* Dedicated VPC endpoint subnet tier

---

# 🔀 Transit Gateway Architecture

The networking layer uses a hub-and-spoke Transit Gateway architecture.

Key concepts implemented:

* Segmented TGW route tables
* Explicit route propagation
* Explicit route associations
* Controlled east-west traffic
* Shared services routing
* Finance and HR isolation
* Manual propagation control

Traffic between business units is intentionally restricted.

Example:

* Production can access shared services
* HR can access shared services
* Finance can access shared services
* HR cannot directly access Production
* Finance cannot directly access Production

This simulates PCI-DSS style network segmentation patterns.

---

# 🔐 Private AWS Connectivity

The environment uses both:

* Gateway VPC Endpoints
* Interface VPC Endpoints

to ensure workloads communicate with AWS services privately through the AWS backbone network instead of traversing the public internet.

Implemented endpoints include:

* S3
* DynamoDB
* CloudWatch Logs
* ECR API
* ECR Docker Registry
* Secrets Manager
* STS
* SQS
* SNS
* Kinesis Streams
* Kinesis Firehose

This architecture reinforces:

* reduced internet exposure
* private service communication
* lower attack surface
* enterprise-grade connectivity patterns

---

# 🛡️ Security Architecture

## Security Principles

* Least privilege routing
* Network segmentation
* Private-only data tier
* Centralized governance
* Immutable logging
* TLS-encrypted service communication
* Explicit route control
* Security-first subnet design

---

# 🔒 Security Controls Implemented

| Control                | Purpose                          |
| ---------------------- | -------------------------------- |
| SCP Restrictions       | Prevent unauthorized actions     |
| CloudTrail Protection  | Prevent audit log deletion       |
| Encryption Enforcement | Secure storage and communication |
| Segmented Route Tables | Control east-west traffic        |
| NAT Isolation          | Controlled outbound access       |
| Interface Endpoints    | Private AWS service access       |
| Dedicated Data Subnets | Isolate sensitive workloads      |
| Security Groups        | Restrict inbound communication   |

---

# 📅 6-Week Enterprise Build Plan

| Week   | Focus Area                            |
| ------ | ------------------------------------- |
| Week 1 | Governance & AWS Organizations        |
| Week 2 | Enterprise Networking & VPC Endpoints |
| Week 3 | Security Architecture & IAM           |
| Week 4 | Production Platform & EKS             |
| Week 5 | Data Platform & Analytics             |
| Week 6 | Disaster Recovery & DevOps Automation |

---

# ✅ Week 1 Completed — Governance Layer

## Implemented

* AWS Organizations
* Organizational Units (OUs)
* Service Control Policies (SCPs)
* Audit account
* Log archive account
* Governance boundaries
* Remote Terraform state strategy

## Key Learning Areas

* Multi-account architecture
* SCP enforcement
* Enterprise governance
* Organizational design patterns

---

# ✅ Week 2 Completed — Enterprise Networking

## Implemented

* Multi-VPC architecture
* Transit Gateway
* TGW segmented routing
* Public/Application/Data subnet tiers
* NAT Gateways
* Route tables
* Route propagation
* Route associations
* Interface VPC Endpoints
* Gateway VPC Endpoints
* Private AWS service connectivity
* CloudWatch private logging access
* ECR private image pull architecture
* Secrets Manager private access

## Key Learning Areas

* Enterprise routing strategy
* Network segmentation
* AWS backbone networking
* Private DNS resolution
* Interface ENI architecture
* Terraform scaling with loops and dynamic logic

---

# 🚀 Technologies Used

## Cloud & Infrastructure

* AWS Organizations
* AWS Transit Gateway
* VPC Endpoints
* Route Tables
* NAT Gateways
* Internet Gateways
* Security Groups
* IAM
* CloudWatch
* ECR
* S3
* DynamoDB
* Kinesis

## Infrastructure as Code

* Terraform
* Variables
* Locals
* for_each loops
* count meta-arguments
* dynamic blocks
* reusable architecture patterns

---

# 📚 Skills Developed

## Cloud Engineering

* AWS Architecture
* Enterprise Networking
* Multi-account governance
* Infrastructure as Code
* Security architecture

## Networking

* CIDR planning
* Subnetting
* Route propagation
* NAT architecture
* Private connectivity
* DNS architecture
* Transit Gateway segmentation

## DevOps & Automation

* Terraform automation
* Reusable code design
* Infrastructure scaling patterns
* Dynamic Terraform logic
* Enterprise IaC structuring

---

# ⚠️ IMPORTANT — Before Deployment

This project was successfully deployed in a live AWS environment on:

📅 May 14, 2026

The example email addresses used in the Terraform configuration are fictional and MUST be replaced with email addresses you control.

## ❌ Do NOT Deploy With Example Emails

Deploying with email addresses you do not own may result in:

* loss of root account access
* inability to configure billing
* locked organization accounts
* AWS Support recovery intervention

## ✅ Recommended Approach

```terraform
log_archive_email = "yourname+log@gmail.com"
audit_email       = "yourname+audit@gmail.com"
```

---

# 🎯 Personal Goal

This project is helping me bridge the gap between:

* traditional networking
* cloud architecture
* infrastructure automation
* enterprise security
* platform engineering

I am documenting the entire journey publicly while learning enterprise AWS architecture from the networking layer upward.

The goal is not only to understand AWS services, but to understand:

* why enterprise systems are designed this way
* how infrastructure dependencies connect
* how networking impacts architecture
* how security integrates into cloud operations

---

# 👨‍💻 Author

## Lerato Motsware

**AWS | Terraform | Networking | Cloud Infrastructure**

National Diploma in Electrical Engineering (Light Current) with experience supporting mission-critical networking and communication infrastructure.

Focused on:

* Cloud Infrastructure Engineering
* Enterprise Networking
* Platform Engineering
* DevOps Automation
* AWS Architecture
* Infrastructure Security

---

# 📌 Repository Status

✅ Week 1 Complete — Governance Layer
✅ Week 2 Complete — Enterprise Networking
🚧 Week 3 In Progress — Security Architecture
