# Week 5: Production Layer — ABSA Enterprise AWS Landing Zone

## Overview

This is **Week 5 of the ABSA Enterprise AWS Landing Zone**. With governance
(Week 1), networking (Week 2), and security (Week 3) established, Week 5
deploys the **production infrastructure** that runs the banking application.

**In plain English:** We're deploying the actual bank. The Kubernetes cluster
that processes payments. The encrypted database that stores transactions.
The Redis cache that makes balance checks instant. The API Gateway that
receives requests from Sipho's phone. The CloudFront CDN that delivers the
app globally. The load balancer that routes traffic to healthy pods.

This is where Sipho's R5,000 transfer actually runs.

---

## What We Built

### 1. EKS Cluster — Kubernetes Control Plane

- **Kubernetes 1.32** — Latest stable version
- **Private endpoint** — No public API server access
- **IRSA enabled** — Pods get their own IAM roles via OIDC
- **Control plane logging** — API, audit, authenticator, controller, scheduler
- **KMS encryption** — Kubernetes secrets encrypted with dedicated KMS key
- **3 EKS add-ons** — VPC CNI, CoreDNS, Kube-proxy

### 2. EKS Node Group — Worker Nodes

- **3 nodes** (1 per AZ) — Auto-scales to 10 during peak
- **Graviton2 instances** — c6i.xlarge/c6i.2xlarge
- **Private subnets only** — No public IPs on nodes
- **Rolling updates** — Zero-downtime node replacements
- **IRSA** — Payment API pod has its own IAM role

### 3. Kubernetes Resources

- **5 namespaces** — payment-api, fraud-detection, notification-service,
  compliance-audit, monitoring
- **Service Account with IRSA** — payment-api-sa linked to IAM role
- **ConfigMap** — Non-sensitive application configuration
- **Kubernetes Secrets** — Database and Redis connection details
- **Horizontal Pod Autoscaler** — 2-20 replicas based on CPU/memory
- **Pod Disruption Budget** — Minimum 2 pods always available

### 4. RDS Aurora PostgreSQL

- **Aurora PostgreSQL 16.4** — 3x throughput of standard PostgreSQL
- **Multi-AZ** — Primary + Replica across Availability Zones
- **KMS encrypted** — Using Week 3 encryption key
- **30-day backups** — Point-in-time recovery
- **Deletion protection** — Prevents accidental destroy
- **IAM authentication** — Pods authenticate with IAM roles
- **Enhanced monitoring** — OS-level metrics every 60 seconds

### 5. ElastiCache Redis

- **Redis 7.1** — Session management and caching
- **Multi-AZ** — Primary + Replica with automatic failover
- **Auth token enabled** — Pods must authenticate
- **Encryption at rest AND in transit** — TLS + KMS
- **7-day snapshots** — Point-in-time recovery
- **volatile-lru eviction** — TTL keys evicted first

### 6. API Gateway

- **REST API** — /api/v1/payments/transfer, /api/v1/accounts/balance
- **VPC Link** — Private connection to internal ALB
- **Request validation** — Rejects malformed requests before reaching pods
- **Throttling** — 10,000 req/sec rate limit
- **10M requests/month quota**
- **Access logging** — Every request logged to CloudWatch

### 7. Application Load Balancer

- **Internet-facing** — Receives traffic from CloudFront
- **Path-based routing** — /payments/* → payment pods, /fraud/* → fraud pods
- **Health checks** — Unhealthy pods removed from rotation
- **Sticky sessions** — 24-hour cookie-based stickiness
- **HTTPS only** — HTTP automatically redirected to HTTPS
- **TLS 1.2+** — Older protocols blocked
- **Access logs** — Every request logged to S3

### 8. CloudFront CDN

- **Global edge network** — 80ms latency from Johannesburg
- **WAF attached** — All 7 Week 3 WAF rules active at the edge
- **Custom domain** — banking.absa.co.za
- **HTTPS only** — TLS 1.2+ enforced
- **Origin protection** — Custom header prevents bypass
- **Caching** — Static assets cached 7 days, API requests never cached
- **Price Class 100** — Cost-optimized for South Africa + UK

---

## Files in This Module

| File | What It Contains |
|------|-----------------|
| `main.tf` | Provider config, remote state from Weeks 1-3, Kubernetes provider |
| `variables.tf` | All configurable inputs with types and defaults |
| `terraform.tfvars` | ABSA-specific production values and cost toggles |
| `locals.tf` | Subnet selection, IAM roles, KMS keys, secrets from Weeks 1-3 |
| `eks_cluster.tf` | EKS control plane, add-ons, IRSA, OIDC provider |
| `eks_node_group.tf` | Worker nodes, namespaces, service accounts, HPA, PDB |
| `rds_aurora.tf` | Aurora PostgreSQL cluster, instances, monitoring |
| `elasticache_redis.tf` | Redis replication group, parameter group |
| `api_gateway.tf` | REST API, resources, methods, VPC Link, usage plan |
| `alb.tf` | Application Load Balancer, target groups, listeners, rules |
| `cloudfront.tf` | CDN distribution, WAF attachment, logging |
| `outputs.tf` | Exports for Week 6 (Data Platform) |
| `README.md` | This file — the complete guide to Week 5 |

---

## How Week 5 Connects to Other Weeks
