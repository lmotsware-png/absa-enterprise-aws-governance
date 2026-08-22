# Week 7: Messaging — ABSA Enterprise AWS Landing Zone

## Overview

This is **Week 7 of the ABSA Enterprise AWS Landing Zone**. With governance,
networking, security, shared services, production, and data platform
established, Week 7 builds the **messaging layer** — the asynchronous
communication backbone that decouples microservices and ensures no
transaction is ever lost.

**In plain English:** When Sipho transfers money, the payment pod doesn't
wait for fraud detection to finish. It publishes an event and moves on.
The messaging layer ensures that event reaches every service that needs it —
even if some services are temporarily down.

---

## What We Built

### 1. SQS Queues (8 total)
- **4 main queues**: fraud-detection, audit-logging, notification, payment-events
- **4 dead letter queues**: one per main queue
- **Redrive policy**: 3 failed attempts → move to DLQ
- **KMS encrypted**: Every message encrypted at rest
- **14-day DLQ retention**: Operations team has time to investigate

### 2. SNS Topics (3 total)
- **Payment Events**: Fans out to all 4 queues
- **Fraud Alerts**: High-risk transaction notifications
- **System Notifications**: Operational alerts

### 3. Amazon MQ
- **ActiveMQ 5.17.6**: Legacy SWIFT/mainframe integration
- **Active-Standby Multi-AZ**: High availability
- **Private**: No internet access
- **KMS encrypted**: At rest

### 4. Queue Policies
- **SNS→SQS permissions**: SNS can write to queues
- **Source ARN conditions**: Only the correct topic can write

---

## The Sipho Story — How Week 7 Handles His Transfer

1. Sipho taps "Transfer R5,000"
2. Payment pod processes transaction
3. Payment pod publishes to `ABSA-Payment-Events` SNS topic
4. SNS fans out to 4 SQS queues simultaneously
5. Fraud detection pod picks up message → processes → deletes
6. Audit pod picks up message → writes to CloudTrail → deletes
7. Notification pod picks up message → sends SMS → deletes
8. Payment events pod picks up message → forwards to Kinesis (Week 6)

If any pod is down: message waits in queue. If message fails 3 times: DLQ. Operations investigates.

---

## Files in This Module

| File | What It Contains |
|------|-----------------|
| `main.tf` | Provider, remote state from Weeks 1-6 |
| `variables.tf` | Queue config, MQ config |
| `terraform.tfvars` | ABSA-specific values |
| `locals.tf` | Queue names, topic names |
| `sqs_queues.tf` | 4 main queues + 4 DLQs |
| `sns_topics.tf` | 3 topics + 4 subscriptions |
| `amazon_mq.tf` | Legacy system broker |
| `queue_policies.tf` | SNS→SQS permissions |
| `outputs.tf` | Exports for Weeks 8-9 |
| `README.md` | This file |

---

## Next: Week 8 — Disaster Recovery

With messaging ensuring no data loss, Week 8 builds:
- Cross-region warm standby in eu-west-1 (Ireland)
- RDS cross-region replication
- S3 Cross-Region Replication
- Route 53 failover
- Recovery procedures

[Continue to Week 8 →](../08-disaster-recovery/README.md)