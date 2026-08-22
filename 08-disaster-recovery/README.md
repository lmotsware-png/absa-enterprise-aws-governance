**Automated steps:** T+0 through T+150 — zero human intervention.

**Manual steps required after T+150:**
1. Remove EKS node taint (allows application pods to schedule)
2. Scale EKS node group from 1 to 3 nodes
3. Promote Aurora DR replica to writer
4. Create DR SQS queues and SNS topics (messaging layer)
5. Notify external partners of NAT Gateway IP change

Total estimated RTO including manual steps: **5-7 minutes**.

---

## 6. Deployment Guide

### 6.1 Initialize

```bash
cd 08-disaster-recovery

terraform init

# Expected output:
# Initializing the backend...
# Initializing provider plugins...
# - Finding hashicorp/aws versions matching "~> 6.22.0"...
# - Installing hashicorp/aws v6.22.x
# Terraform has been successfully initialized!
```

### 6.2 Plan

```bash
terraform plan -out=week8.tfplan

# Review carefully:
# - Resources being created in eu-west-1 (provider: aws.dr)
# - Resources being created in us-east-1 (provider: aws.us_east_1)
# - Resources modifying af-south-1 source buckets (replication config)
# - Expected: ~65-75 resources to add
```

### 6.3 Apply

```bash
terraform apply week8.tfplan

# Expected duration: 25-40 minutes
# Longest operations:
#   - Aurora cross-region replica:  15-20 minutes (initial sync)
#   - ACM certificate validation:   2-5 minutes
#   - EKS cluster creation:         10-15 minutes
#   - EKS node group:               3-5 minutes
```

### 6.4 Verify Deployment

```bash
# 1. Verify DR Aurora replica is replicating
aws rds describe-db-clusters \
  --db-cluster-identifier absa-dr-aurora \
  --region eu-west-1 \
  --query "DBClusters[0].{Status:Status,ReplicationSource:ReplicationSourceIdentifier}"

# Expected:
# {
#   "Status": "available",
#   "ReplicationSource": "arn:aws:rds:af-south-1:123456789012:cluster:absa-production-aurora"
# }

# 2. Verify S3 replication is active
aws s3api get-bucket-replication \
  --bucket absa-cloudtrail-logs-123456789012 \
  --query "ReplicationConfiguration.Rules[0].Status"
# Expected: "Enabled"

# 3. Verify Route53 health checks
aws route53 get-health-check-status \
  --health-check-id <route53_primary_health_check_id from outputs>
# Expected: StatusList with HealthCheckObservations showing "Success"

# 4. Verify DR EKS cluster
aws eks describe-cluster \
  --name absa-production-eks-dr \
  --region eu-west-1 \
  --query "cluster.status"
# Expected: "ACTIVE"

# 5. Check DR readiness alarm
aws cloudwatch describe-alarms \
  --alarm-names "ABSA-DR-Overall-Readiness" \
  --region eu-west-1 \
  --query "CompositeAlarms[0].StateValue"
# Expected: "OK"
```

### 6.5 Subscribe Operations Team to SNS Topics

```bash
# DR infrastructure alerts (eu-west-1)
aws sns subscribe \
  --topic-arn <dr_ops_sns_topic_arn from outputs> \
  --protocol email \
  --notification-endpoint dr-ops@absa.co.za \
  --region eu-west-1

# DR database alerts (eu-west-1)
aws sns subscribe \
  --topic-arn <dr_alerts_sns_topic_arn from outputs> \
  --protocol email \
  --notification-endpoint dba-team@absa.co.za \
  --region eu-west-1

# Route53 failover alerts (us-east-1)
aws sns subscribe \
  --topic-arn <route53_alerts_sns_topic_arn from outputs> \
  --protocol email \
  --notification-endpoint on-call@absa.co.za \
  --region us-east-1

# CloudFront alerts (us-east-1)
aws sns subscribe \
  --topic-arn <dr_ops_us_east_1_sns_topic_arn from outputs> \
  --protocol email \
  --notification-endpoint sre-team@absa.co.za \
  --region us-east-1
```

---

## 7. DR Activation Runbook

> ⚠️ **This runbook is executed when af-south-1 is unavailable and Route53 has automatically rerouted traffic to eu-west-1.**
>
> DNS failover (Steps 1-2) is automatic. Steps 3-6 require human action.

### 7.1 Step 1 — Confirm Failover is Active (Automatic)

DNS failover happens automatically. Confirm it has triggered:

```bash
# Check current DNS resolution
dig banking.absa.co.za

# If failover is active, the A record resolves to DR CloudFront IPs.
# The answer section should show CloudFront edge IPs (not primary).

# Check Route53 health check status
aws route53 get-health-check-status \
  --health-check-id <route53_primary_health_check_id> \
  --query "HealthCheckObservations[*].StatusReport.Status"
# If failover triggered: one or more "Failure" statuses

# Check CloudWatch alarm
aws cloudwatch describe-alarms \
  --alarm-names "ABSA-DR-Primary-Health-Check-Failed" \
  --region us-east-1 \
  --query "MetricAlarms[0].StateValue"
# If failover triggered: "ALARM"
```

### 7.2 Step 2 — Remove EKS Node Taint

The warm standby EKS node is tainted `dr-standby=true:NoSchedule`. Remove the taint to allow application pods to schedule:

```bash
# Update kubeconfig for DR cluster
aws eks update-kubeconfig \
  --name absa-production-eks-dr \
  --region eu-west-1

# Verify node is present and ready
kubectl get nodes

# Remove the warm standby taint from all nodes
kubectl taint nodes --all dr-standby=true:NoSchedule-

# Verify taint is removed
kubectl describe nodes | grep Taints
# Expected: Taints: <none>
```

### 7.3 Step 3 — Promote Aurora Replica

The DR Aurora cluster is currently a read-only replica. Promote it to an independent writer:

```bash
# Promote the DR cluster (removes replication, makes it standalone writer)
aws rds promote-read-replica-db-cluster \
  --db-cluster-identifier absa-dr-aurora \
  --region eu-west-1

# Monitor promotion status (takes 1-3 minutes)
aws rds describe-db-clusters \
  --db-cluster-identifier absa-dr-aurora \
  --region eu-west-1 \
  --query "DBClusters[0].{Status:Status,ReplicationSource:ReplicationSourceIdentifier}"

# Wait until:
# Status: "available"
# ReplicationSource: null (no longer a replica)

# Get the promoted cluster's writer endpoint
aws rds describe-db-clusters \
  --db-cluster-identifier absa-dr-aurora \
  --region eu-west-1 \
  --query "DBClusters[0].Endpoint"
```

### 7.4 Step 4 — Scale EKS Node Group

Scale from warm standby (1 node) to production capacity (3 nodes):

```bash
# Scale node group to production capacity
aws eks update-nodegroup-config \
  --cluster-name absa-production-eks-dr \
  --nodegroup-name absa-dr-nodes \
  --scaling-config desiredSize=3,minSize=1,maxSize=6 \
  --region eu-west-1

# Monitor scale-out (takes ~3 minutes)
aws eks describe-nodegroup \
  --cluster-name absa-production-eks-dr \
  --nodegroup-name absa-dr-nodes \
  --region eu-west-1 \
  --query "nodegroup.{Status:status,DesiredSize:scalingConfig.desiredSize}"

# Wait until Status: "ACTIVE" and DesiredSize: 3

# Verify all nodes joined the cluster
kubectl get nodes --watch
# Expected: 3 nodes in Ready state
```

### 7.5 Step 5 — Deploy Application Pods

Application pods must be deployed to the DR cluster. They use the same container images as production (pulled from the primary region's ECR via ECR cross-region replication or a separate DR ECR repository).

```bash
# Apply the application Kubernetes manifests
# These should be in your GitOps repository
kubectl apply -f k8s/namespaces/
kubectl apply -f k8s/payment-api/
kubectl apply -f k8s/fraud-detection/
kubectl apply -f k8s/notification-service/

# Verify pods are running
kubectl get pods --all-namespaces

# Check pod logs for Aurora connectivity
kubectl logs -n payment-api \
  -l app=payment-api \
  --tail=50
# Look for: "Database connection established"
```

### 7.6 Step 6 — Notify External Partners

ABSA's banking operations involve external systems that connect from ABSA's egress IPs. The DR NAT Gateways have different public IPs than the primary NAT Gateways.

```bash
# Get DR NAT Gateway public IPs
terraform output dr_nat_gateway_public_ips

# Notify:
# - Payment network gateways (Visa, Mastercard)
# - SWIFT network operators
# - Core banking system vendors
# - Internal partner teams

# Typical notification:
# "ABSA is operating in DR mode from eu-west-1.
#  Outbound IPs have changed to: [IP1], [IP2], [IP3].
#  Please allowlist these IPs immediately."
```

### 7.7 Step 7 — Verify End-to-End

```bash
# 1. Test the banking endpoint from outside
curl -I https://banking.absa.co.za/health
# Expected: HTTP 200

# 2. Run a synthetic transaction test
# (use your existing integration test suite against DR)
npm run test:integration -- --env=dr

# 3. Check CloudWatch dashboard
# Open: https://eu-west-1.console.aws.amazon.com/cloudwatch/home
#        ?region=eu-west-1#dashboards:name=ABSA-DR-Infrastructure-Health

# 4. Verify DR CloudFront error rate is acceptable
aws cloudwatch get-metric-statistics \
  --namespace AWS/CloudFront \
  --metric-name 5xxErrorRate \
  --dimensions Name=DistributionId,Value=<dr_cloudfront_distribution_id> \
               Name=Region,Value=Global \
  --start-time $(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Average \
  --region us-east-1
# Expected: < 1%
```

---

## 8. DR Deactivation — Failing Back to Primary

> ⚠️ **Failback to primary should only begin after af-south-1 is confirmed healthy.**

### 8.1 Verify Primary is Healthy

```bash
# Check primary Aurora is available
aws rds describe-db-clusters \
  --db-cluster-identifier absa-production-aurora \
  --region af-south-1 \
  --query "DBClusters[0].Status"
# Expected: "available"

# Check Route53 primary health check
aws cloudwatch describe-alarms \
  --alarm-names "ABSA-DR-Primary-Health-Check-Failed" \
  --region us-east-1 \
  --query "MetricAlarms[0].StateValue"
# Expected: "OK" (primary is healthy again)
```

### 8.2 Re-establish Aurora Replication

After promotion, the DR Aurora is an independent cluster. To make it a replica again:

```bash
# Create a new cross-region replica pointing at the primary
# (the original replication_source_identifier was removed at promotion)
aws rds create-db-cluster \
  --db-cluster-identifier absa-dr-aurora-v2 \
  --engine aurora-postgresql \
  --engine-version 16.4 \
  --replication-source-identifier \
    arn:aws:rds:af-south-1:123456789012:cluster:absa-production-aurora \
  --region eu-west-1

# This re-establishes replication from the primary
# Any transactions written to DR during failover period
# must be manually reconciled before this step
```

### 8.3 Re-add EKS Taint

```bash
# Re-taint DR nodes to return to warm standby mode
kubectl taint nodes --all \
  dr-standby=true:NoSchedule

# Scale back to warm standby count
aws eks update-nodegroup-config \
  --cluster-name absa-production-eks-dr \
  --nodegroup-name absa-dr-nodes \
  --scaling-config desiredSize=1,minSize=1,maxSize=6 \
  --region eu-west-1
```

### 8.4 Route53 Failback

Route53 fails back automatically once the primary health check returns to healthy. No manual DNS changes are needed — when `banking.absa.co.za/health` returns 200 for 3 consecutive checks, Route53 resumes serving the PRIMARY record.

---

## 9. Monitoring and Alerting

### 9.1 DR Health Dashboard

**URL:** `https://eu-west-1.console.aws.amazon.com/cloudwatch/home?region=eu-west-1#dashboards:name=ABSA-DR-Infrastructure-Health`

The dashboard shows in real time:
- Aurora replication lag vs RPO threshold (red line at 300s)
- Aurora CPU utilization
- Aurora database connections
- NLB healthy host count
- NLB active flow count (non-zero means DR is serving traffic)
- S3 CloudTrail replication latency vs 15-minute SLA
- All alarm statuses

### 9.2 Alarm Reference

| Alarm Name | Region | Threshold | Meaning |
|-----------|--------|-----------|---------|
| ABSA-DR-RDS-Replication-Lag | eu-west-1 | > 300s for 2 min | RPO at risk |
| ABSA-DR-RDS-Replica-Not-Replicating | eu-west-1 | < 1 connection for 15 min | Replication stopped |
| ABSA-DR-Aurora-Low-Storage | eu-west-1 | < 5GB free | Storage pressure |
| ABSA-DR-Aurora-High-CPU | eu-west-1 | > 80% for 15 min | Compute pressure |
| ABSA-DR-Aurora-Low-Memory | eu-west-1 | < 256MB for 10 min | Memory pressure |
| ABSA-DR-CloudTrail-Replication-Latency | af-south-1 | > 900s for 10 min | S3 CRR slow |
| ABSA-DR-CloudTrail-Replication-Failed | af-south-1 | > 0 failures | S3 CRR broken |
| ABSA-DR-EKS-Node-Count-Low | eu-west-1 | < 1 node for 10 min | Warm standby down |
| ABSA-DR-NLB-No-Healthy-Hosts | eu-west-1 | < 1 host for 2 min | DR traffic path broken |
| ABSA-DR-CloudFront-High-Error-Rate | us-east-1 | > 5% for 10 min | DR site returning errors |
| ABSA-DR-Primary-Health-Check-Failed | us-east-1 | Status = 0 | **Failover triggered** |
| ABSA-DR-DR-Health-Check-Failed | us-east-1 | Status = 0 for 2 min | DR site has issues |
| ABSA-DR-Overall-Readiness | eu-west-1 | Any child in ALARM | DR not fully ready |

### 9.3 SNS Topic Reference

| Topic Name | Region | Alarm Source |
|-----------|--------|-------------|
| ABSA-DR-Alerts | eu-west-1 | RDS replication alarms |
| ABSA-DR-Operations | eu-west-1 | EKS, NLB, Aurora health alarms |
| ABSA-DR-Operations-CloudFront | us-east-1 | CloudFront error + latency alarms |
| ABSA-Route53-Failover-Alerts | us-east-1 | Route53 health check alarms |

---

## 10. Cost Reference

### Monthly Cost Breakdown (All Toggles Enabled)

| Component | Resource | Cost/Month |
|-----------|----------|-----------|
| DR VPC | NAT Gateways × 3 | ~$96 |
| DR VPC | Interface VPC Endpoints × 6 | ~$52 |
| DR RDS | db.r6g.large replica | ~$175 |
| DR EKS | Control plane | ~$73 |
| DR EKS | c6i.xlarge node × 1 | ~$120 |
| DR NLB | Network load balancer | ~$18 |
| DR CloudFront | Minimal traffic during standby | ~$1 |
| DR KMS | 3 keys × $1 | ~$3 |
| S3 CRR | Replication + RTC charges | ~$15 |
| Route53 | Health checks × 2 | ~$1 |
| CloudWatch | Alarms, dashboard, logs | ~$1 |
| **Total** | | **~$555/month** |

### Cost Reduction Options

| Toggle | Savings | Trade-off |
|--------|---------|-----------|
| `enable_dr_eks = false` | ~$211/month | RTO increases to 30-60 min |
| Remove Interface VPC Endpoints | ~$52/month | Traffic goes via NAT |
| **Minimum viable DR** | **~$292/month** | EKS not pre-provisioned |

---

## 11. Connections to Prior Weeks

| Prior Week | What Week 8 Consumes |
|-----------|---------------------|
| Week 1 — Governance | CloudTrail covers eu-west-1 automatically. SCPs apply to DR resources. |
| Week 2 — Networking | CIDR design mirrored (100-offset). Security group pattern replicated. Subnet tier structure identical. |
| Week 3 — Security | KMS key pattern replicated for 3 DR keys. WAF (`waf_acl_arn`) attached to DR CloudFront. IAM role patterns replicated for DR EKS and IRSA. |
| Week 4 — Shared Services | CloudTrail and Config buckets are CRR **sources**. Week 4 must have versioning enabled (see Prerequisites). Outputs provide `cloudtrail_bucket_name`, `cloudtrail_bucket_arn`, `config_bucket_name`, `config_bucket_arn`. |
| Week 5 — Production | Aurora cluster ID is the `replication_source_identifier`. EKS cluster name forms DR cluster name. Primary CloudFront domain is the PRIMARY failover alias. Primary API endpoint is monitored by Route53 health check. |
| Week 6 — Data Platform | Not consumed in Week 8. Analytical DR (Redshift, OpenSearch) is out of scope. Firehose bucket CRR is a recommended Week 9 addition. |
| Week 7 — Messaging | Not consumed in Week 8. SQS queues and SNS topics are recreated in DR region during failover activation (Step 5 of runbook). |

---

## 12. Known Limitations

### 1. Terraform State in Primary Region
The `08-disaster-recovery/terraform.tfstate` file is stored in `absa-terraform-state-af-south-1` in `af-south-1`. If Cape Town is unavailable, `terraform apply` cannot run.

**Mitigation:** Failover is fully automatic via Route53 health checks. Terraform is not required for the failover to occur or for traffic to reach the DR site. Manual steps (Aurora promotion, EKS scale-out) use AWS CLI directly, not Terraform.

**Future fix:** Replicate the state bucket to eu-west-1 using S3 CRR, or move Week 8 state to a dedicated eu-west-1 state bucket.

### 2. Messaging Layer Not Replicated
Week 7's SQS queues and SNS topics are not replicated to eu-west-1. They must be recreated during DR activation.

**Mitigation:** Application pods in the DR EKS cluster will fail to connect to messaging services until Step 5 of the runbook creates DR versions of the queues and topics. Payment processing works without messaging (transactions commit) but notifications and audit logging are delayed until messaging is restored.

### 3. Aurora Promotion Creates Data Gap
Transactions written to the primary Aurora between the last successful replication and the failover are lost. The RPO target is 5 minutes — this data must be reconciled manually from payment network logs.

**Mitigation:** Work with ABSA's payment operations team to reconcile the gap period transactions from SWIFT and payment gateway records.

### 4. EKS Container Images
DR EKS pods pull container images from ECR. The primary region's ECR repositories must be replicated to eu-west-1, or pods must be configured to pull from the primary region's ECR cross-region.

**Mitigation:** Configure ECR replication from af-south-1 to eu-west-1 for all application image repositories. This is a recommended addition to Week 5's ECR configuration.

### 5. Composite Alarm Logic
The `ABSA-DR-Overall-Readiness` composite alarm uses `AND` logic — it fires only when all child alarms are simultaneously in ALARM. The intended behavior is `OR` (fire when any child alarms).

**Fix:** Update `alarm_rule` in `dr_health_checks.tf` to use `OR` between alarm conditions.

---

## 13. Troubleshooting

### Aurora Replica Not Replicating

```bash
# Check replication status
aws rds describe-db-clusters \
  --db-cluster-identifier absa-dr-aurora \
  --region eu-west-1 \
  --query "DBClusters[0].{Status:Status,ReplicationSource:ReplicationSourceIdentifier,Lag:ReaderEndpoint}"

# Common causes:
# 1. Primary cluster has binlog retention set too low
#    Fix: Ensure Week 5 Aurora has backup_retention_period >= 1 day
# 2. Network connectivity between regions
#    Fix: Check VPC endpoint connectivity and security group rules
# 3. KMS key policy not allowing cross-region replication service
#    Fix: Verify kms_key_id in dr cluster matches aws_kms_key.dr_rds.arn
```

### S3 Replication Not Working

```bash
# Check replication configuration on source bucket
aws s3api get-bucket-replication \
  --bucket absa-cloudtrail-logs-123456789012

# Check replication metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/S3 \
  --metric-name OperationsPendingReplication \
  --dimensions \
    Name=SourceBucket,Value=absa-cloudtrail-logs-123456789012 \
    Name=DestinationBucket,Value=absa-dr-cloudtrail-logs-123456789012 \
    Name=RuleId,Value=cloudtrail-cape-town-to-ireland \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Sum \
  --region af-south-1

# Common causes:
# 1. Source bucket versioning not enabled
#    Fix: Apply Week 4 additions (s3_log_archive.tf versioning resources)
# 2. IAM replication role missing permissions
#    Fix: Verify ABSA-S3-CRR-Replication-Role policy has all required actions
# 3. Destination bucket policy not allowing replication role
#    Fix: Verify aws_s3_bucket_policy resources in s3_cross_region.tf are applied
```

### Route53 Health Check Failing Unexpectedly

```bash
# Get health check observations from all Route53 checkers
aws route53 get-health-check-status \
  --health-check-id <health_check_id> \
  --query "HealthCheckObservations[*].{Region:IPAddress,Status:StatusReport.Status}"

# Common causes:
# 1. /health endpoint not returning 200
#    Fix: Verify the application's health endpoint is functioning
# 2. TLS certificate error
#    Fix: Verify ACM certificate is ISSUED and covers banking.absa.co.za
# 3. WAF blocking Route53 health check IPs
#    Fix: Route53 health checkers use known IP ranges — verify WAF rules
#         are not blocking these ranges
```

### EKS Pods Not Scheduling After Taint Removal

```bash
# Check pod events for scheduling failures
kubectl describe pods -n payment-api

# Check node capacity
kubectl describe nodes

# Common causes:
# 1. Taint not fully removed
#    Fix: kubectl taint nodes --all dr-standby=true:NoSchedule-
# 2. Insufficient node resources (still only 1 node)
#    Fix: Scale node group to 3 before applying manifests
# 3. Image pull failures (ECR not replicated to eu-west-1)
#    Fix: Configure ECR cross-region replication or use image mirrors
```

---

## Quick Reference Card