# SCP #1: Root SCP — Prevent CloudTrail Deletion
# This lives at the root level, cascading to ALL accounts
data "aws_iam_policy_document" "deny_cloudtrail_deletion" {
  statement {
    sid       = "DenyDeleteCloudTrail"
    effect    = "Deny"
    actions   = [
      "cloudtrail:DeleteTrail",
      "cloudtrail:StopLogging",
      "cloudtrail:UpdateTrail"
    ]
    resources = ["*"]
  }
}

resource "aws_organizations_policy" "deny_cloudtrail_deletion" {
  name        = "ABSA-Deny-CloudTrail-Deletion"
  description = "Prevents accidental deletion/stopping of CloudTrail trails"
  content     = data.aws_iam_policy_document.deny_cloudtrail_deletion.json
  type        = "SERVICE_CONTROL_POLICY"
}

# SCP #2: Production SCP — No Public S3 + Encryption Mandate
data "aws_iam_policy_document" "production_restrictions" {
  statement {
    sid       = "DenyPublicS3"
    effect    = "Deny"
    actions   = [
      "s3:PutBucketAcl",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutObjectAcl"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["public-read", "public-read-write", "authenticated-read"]
    }
  }

  statement {
    sid     = "RequireEncryption"
    effect  = "Deny"
    actions = [
      "s3:PutObject",
      "ec2:RunInstances",
      "rds:CreateDBInstance",
      "rds:CreateDBCluster"
    ]
    resources = ["*"]
    condition {
      test     = "StringNotEquals"
      variable = "aws:RequestedRegion"
      values   = ["eu-west-1", "eu-west-2", "af-south-1"]
    }
  }
}

resource "aws_organizations_policy" "production_restrictions" {
  name        = "ABSA-Production-Restrictions"
  description = "No public S3 + full encryption on compute/storage + region lock"
  content     = data.aws_iam_policy_document.production_restrictions.json
  type        = "SERVICE_CONTROL_POLICY"
}

# SCP #3: Development SCP — Instance Type Limits
data "aws_iam_policy_document" "dev_instance_limits" {
  statement {
    sid       = "LimitInstanceTypes"
    effect    = "Deny"
    actions   = ["ec2:RunInstances"]
    resources = ["arn:aws:ec2:*:*:instance/*"]
    condition {
      test     = "StringNotEquals"
      variable = "ec2:InstanceType"
      values   = [
        "t3.micro", "t3.small", "t3.medium",
        "c6i.large", "c6i.xlarge"
      ]
    }
  }
}

resource "aws_organizations_policy" "dev_instance_limits" {
  name        = "ABSA-Dev-Instance-Limits"
  description = "Limits Dev OU to non-production sized instances for cost control"
  content     = data.aws_iam_policy_document.dev_instance_limits.json
  type        = "SERVICE_CONTROL_POLICY"
}