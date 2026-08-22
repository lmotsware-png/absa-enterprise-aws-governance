# Week 6: Data Platform — ABSA Enterprise AWS Landing Zone

## Overview

This is **Week 6 of the ABSA Enterprise AWS Landing Zone**. With governance,
networking, security, shared services, and production established, Week 6
builds the **data platform** — the analytics brain that turns Sipho's
transactions into business intelligence, compliance reports, and real-time
fraud alerts.

**In plain English:** Week 5 runs the bank. Week 6 understands the bank.

---

## What We Built

### 1. Kinesis Data Streams
- **Real-time transaction streaming** — Every payment flows through
- **On-demand capacity** — Auto-scales during month-end and Black Friday
- **KMS encrypted** — Data protected at rest in the stream
- **24-hour retention** — Long enough for real-time analytics

### 2. Kinesis Data Firehose
- **Batch delivery to S3** — Efficient, compressed, partitioned
- **Hive-compatible prefixes** — `year=/month=/day=/hour=/`
- **GZIP compression** — 75% storage savings
- **KMS encryption** — Every object encrypted at rest

### 3. Kinesis Data Analytics
- **Real-time SQL on transactions** — Fraud scoring as it happens
- **High-risk output** — Suspicious transactions flagged immediately
- **CloudWatch metrics** — Application health monitored

### 4. Redshift Data Warehouse
- **Multi-node cluster** — 2 ra3.xlplus nodes
- **KMS encrypted** — Every block on disk protected
- **Private subnets** — No internet access
- **7-day snapshots** — Point-in-time recovery

### 5. Athena
- **Serverless SQL** — Query CloudTrail, Config, Flow Logs directly from S3
- **Named queries** — Pre-built SQL for common analysis
- **KMS encrypted results** — Even temporary outputs protected

### 6. OpenSearch
- **Log analytics** — Full-text search across all logs
- **Zone-aware** — 3 data nodes across 3 AZs
- **Dedicated masters** — 3 master nodes for cluster management
- **KMS encryption** — At rest and node-to-node
- **HTTPS only** — TLS 1.2+ enforced

### 7. QuickSight
- **Enterprise edition** — SPICE engine, ML Insights
- **Athena + Redshift data sources** — Unified analytics
- **Analyst group** — Permission-based dashboard access

---

## The Sipho Story — What Week 6 Captures

When Sipho transfers R5,000:

1. **Kinesis Stream** receives the transaction event in real time
2. **Kinesis Analytics** runs SQL: "Is this suspicious?" — No (fraud_score: 2)
3. **Firehose** delivers the transaction to S3 within 60 seconds
4. **Redshift** loads the transaction via COPY command
5. **Athena** can query the raw transaction from S3 immediately
6. **OpenSearch** indexes the transaction log for operational search
7. **QuickSight** updates the dashboard — "Transactions Today: +1"

All within minutes of Sipho seeing "Payment successful."

---

## Files in This Module

| File | What It Contains |
|------|-----------------|
| `main.tf` | Provider, remote state from Weeks 1-5 |
| `variables.tf` | Stream config, Redshift sizing, toggles |
| `terraform.tfvars` | ABSA-specific values and cost estimates |
| `locals.tf` | Bucket names, VPC info, KMS keys |
| `iam_roles.tf` | Firehose, Athena, Redshift, Kinesis Analytics roles |
| `kinesis_streams.tf` | Real-time transaction stream |
| `kinesis_firehose.tf` | S3 delivery with partitioning |
| `kinesis_analytics.tf` | Real-time SQL fraud detection |
| `redshift.tf` | Multi-node data warehouse |
| `athena.tf` | Serverless SQL with named queries |
| `opensearch.tf` | Log analytics and full-text search |
| `quicksight.tf` | BI dashboards |
| `outputs.tf` | Exports for Weeks 7-9 |
| `README.md` | This file |

---

## Deployment

```bash
cd 06-data-platform
terraform init
terraform plan -var-file="terraform.tfvars"
terraform apply -var-file="terraform.tfvars"