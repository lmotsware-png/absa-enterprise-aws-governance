# 💰 Cost Analysis — ABSA Enterprise AWS Landing Zone

## Purpose

This document provides estimated AWS infrastructure costs for the ABSA Enterprise AWS Landing Zone project.

The objective is to demonstrate:

* enterprise cloud cost awareness
* infrastructure budgeting considerations
* architectural tradeoffs
* FinOps thinking
* operational planning

All estimates are approximate and based on:

* low-to-moderate lab usage
* AWS Ireland (`eu-west-1`)
* Terraform-managed infrastructure
* limited production-scale traffic

---

# 📅 Current Deployment Status

| Week                           | Status         |
| ------------------------------ | -------------- |
| Week 1 — Governance Layer      | ✅ Complete     |
| Week 2 — Enterprise Networking | ✅ Complete     |
| Week 3 — Security Layer        | 🚧 In Progress |

---

# 🏛️ Week 1 — Governance Layer Cost Analysis

## Services Deployed

* AWS Organizations
* Organizational Units (OUs)
* Service Control Policies (SCPs)
* IAM structures
* Basic governance architecture

---

## Estimated Monthly Cost

| Service                            | Estimated Cost |
| ---------------------------------- | -------------- |
| AWS Organizations                  | Free           |
| SCPs                               | Free           |
| Organizational Units               | Free           |
| IAM                                | Free           |
| Terraform State (minimal S3 usage) | <$1            |
| DynamoDB State Locking             | <$1            |

### Estimated Total:

```text id="1b8jxw"
~ $0 – $2/month
```

---

# 🌐 Week 2 — Enterprise Networking Cost Analysis

## Services Deployed

* Multi-VPC Architecture
* Transit Gateway
* NAT Gateways
* Internet Gateways
* Route Tables
* Route Propagation
* Interface VPC Endpoints
* Gateway VPC Endpoints
* Security Groups
* Private AWS Service Connectivity

---

# ⚠️ Major Cost Drivers

The following services introduce real operational cost:

| Service             | Why It Costs                     |
| ------------------- | -------------------------------- |
| NAT Gateway         | Hourly billing + data processing |
| Transit Gateway     | Attachment + traffic processing  |
| Interface Endpoints | Hourly ENI charges               |
| CloudWatch Logs     | Data ingestion/storage           |
| Cross-AZ Traffic    | Inter-AZ data transfer           |
| Elastic IPs         | Unattached EIPs billed           |

---

# 💵 Estimated Monthly Cost Breakdown

## NAT Gateways

Architecture:

* 1 NAT Gateway per Availability Zone
* 3 Availability Zones total

| Resource    | Quantity | Approx Cost     |
| ----------- | -------- | --------------- |
| NAT Gateway | 3        | ~$95–$110/month |

### Notes

NAT Gateways are one of the most expensive networking components in AWS.

They are required for:

* private subnet outbound internet access
* package updates
* container image pulls
* controlled egress traffic

---

## Transit Gateway

| Resource        | Estimated Cost |
| --------------- | -------------- |
| TGW Attachments | ~$30–$50/month |
| Data Processing | Variable       |

### Notes

Transit Gateway pricing scales with:

* attached VPCs
* inter-VPC traffic volume

---

## Interface VPC Endpoints

Implemented endpoints include:

* STS
* ECR API
* ECR Docker
* CloudWatch Logs
* Secrets Manager
* SNS
* SQS
* Kinesis

| Resource            | Estimated Cost |
| ------------------- | -------------- |
| Interface Endpoints | ~$40–$90/month |

### Notes

Interface Endpoints create Elastic Network Interfaces (ENIs) inside subnets.

Pricing includes:

* hourly endpoint cost
* data processing cost

---

## Gateway Endpoints

| Resource                  | Cost |
| ------------------------- | ---- |
| S3 Gateway Endpoint       | Free |
| DynamoDB Gateway Endpoint | Free |

### Notes

Gateway endpoints are significantly cheaper than Interface Endpoints.

---

## CloudWatch Logs

| Resource              | Estimated Cost |
| --------------------- | -------------- |
| Log ingestion/storage | ~$5–$20/month  |

Depends heavily on:

* workload volume
* retention configuration
* application verbosity

---

# 📊 Estimated Total Cost — Week 2

| Environment Type | Estimated Monthly Cost           |
| ---------------- | -------------------------------- |
| Lab / Low Usage  | ~$150–$250/month                 |
| Moderate Testing | ~$300–$500/month                 |
| Enterprise Scale | Much higher depending on traffic |

---

# 🧠 Key Cost Optimization Lessons

This project demonstrates several real-world cloud engineering lessons:

## 1. Networking Costs Matter

Enterprise networking becomes expensive quickly.

Especially:

* NAT Gateways
* Transit Gateway
* Interface Endpoints
* Cross-AZ traffic

---

## 2. Architecture Decisions Affect Budget

For example:

* choosing NAT instances vs NAT Gateways
* using fewer Availability Zones
* minimizing Interface Endpoints
* reducing inter-VPC traffic

all impact operational cost.

---

## 3. Security and Cost Are Connected

More secure enterprise architectures often introduce:

* more segmentation
* more endpoints
* more routing controls
* more inspection layers

which increases infrastructure cost.

---

# 🛡️ Educational Purpose

This project is designed for:

* enterprise cloud learning
* infrastructure engineering practice
* Terraform architecture design
* networking and security understanding

It is NOT intended for production deployment without:

* proper cost optimization
* workload sizing
* traffic analysis
* enterprise review

---

# 📌 Personal Learning Outcome

One of the biggest realizations during this project:

> Enterprise cloud architecture is not only about deploying infrastructure — it is also about understanding operational cost, scalability, security, and long-term maintainability.

Understanding:

* networking
* routing
* segmentation
* endpoints
* NAT design
* private connectivity

also means understanding:

* cost implications
* scalability tradeoffs
* operational overhead

which are critical in real enterprise cloud environments.
