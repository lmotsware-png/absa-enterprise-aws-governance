# ============================================
# Lambda Auto-Remediation — Automatic Security Fixes
# ============================================

# Lambda IAM Role — Shared by all remediation functions
resource "aws_iam_role" "remediation" {
  name = "ABSA-Remediation-Lambda-Role"
  path = "/service-roles/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "ABSA-Remediation-Lambda-Role"
  })
}

# Lambda Policy — What remediation functions can do
resource "aws_iam_role_policy" "remediation" {
  name = "ABSA-Remediation-Policy"
  role = aws_iam_role.remediation.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketAcl",
          "s3:GetBucketPublicAccessBlock",
          "s3:PutBucketPublicAccessBlock"
        ]
        Resource = "arn:aws:s3:::*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:GetAccessKeyLastUsed",
          "iam:UpdateAccessKey",
          "iam:ListAccessKeys"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.remediation_alerts.arn
      }
    ]
  })
}

# SNS Topic for remediation alerts
resource "aws_sns_topic" "remediation_alerts" {
  name = "ABSA-Remediation-Alerts"

  tags = merge(local.common_tags, {
    Name = "ABSA-Remediation-Alerts"
  })
}

# ============================================
# Remediation Function 1: Block Public S3 Buckets
# ============================================

resource "aws_lambda_function" "block_public_s3" {
  function_name = "ABSA-Block-Public-S3"
  description   = "Automatically blocks public S3 buckets when detected"
  runtime       = "python3.12"
  handler       = "index.handler"
  role          = aws_iam_role.remediation.arn
  timeout       = 30
  memory_size   = 128

  filename         = data.archive_file.block_public_s3.output_path
  source_code_hash = data.archive_file.block_public_s3.output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.remediation_alerts.arn
    }
  }

  tags = merge(local.common_tags, {
    Name = "ABSA-Block-Public-S3"
  })
}

# Lambda code — packaged as a zip
data "archive_file" "block_public_s3" {
  type        = "zip"
  output_path = "${path.module}/lambda/block_public_s3.zip"

  source {
    content = <<-PYTHON
import boto3
import os

def handler(event, context):
    s3 = boto3.client('s3')
    sns = boto3.client('sns')
    
    # Get bucket name from the CloudTrail event
    bucket_name = event['detail']['requestParameters']['bucketName']
    
    print(f"Remediating public bucket: {bucket_name}")
    
    # Block all public access
    s3.put_public_access_block(
        Bucket=bucket_name,
        PublicAccessBlockConfiguration={
            'BlockPublicAcls': True,
            'IgnorePublicAcls': True,
            'BlockPublicPolicy': True,
            'RestrictPublicBuckets': True
        }
    )
    
    # Send notification
    sns.publish(
        TopicArn=os.environ['SNS_TOPIC_ARN'],
        Subject=f"REMEDIATED: Public S3 bucket {bucket_name}",
        Message=f"Auto-remediation: Blocked public access on bucket {bucket_name}.\n"
                f"The bucket was detected as public and has been automatically secured."
    )
    
    print(f"Remediation complete for: {bucket_name}")
    
    return {
        'statusCode': 200,
        'body': f'Public access blocked on {bucket_name}'
    }
PYTHON
    filename = "index.py"
  }
}

# ============================================
# Remediation Function 2: Revoke Unused IAM Keys
# ============================================

resource "aws_lambda_function" "revoke_unused_iam" {
  function_name = "ABSA-Revoke-Unused-IAM"
  description   = "Revokes IAM access keys unused for 90+ days"
  runtime       = "python3.12"
  handler       = "index.handler"
  role          = aws_iam_role.remediation.arn
  timeout       = 60
  memory_size   = 128

  filename         = data.archive_file.revoke_unused_iam.output_path
  source_code_hash = data.archive_file.revoke_unused_iam.output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.remediation_alerts.arn
      MAX_UNUSED_DAYS = "90"
    }
  }

  tags = merge(local.common_tags, {
    Name = "ABSA-Revoke-Unused-IAM"
  })
}

data "archive_file" "revoke_unused_iam" {
  type        = "zip"
  output_path = "${path.module}/lambda/revoke_unused_iam.zip"

  source {
    content = <<-PYTHON
import boto3
import os
from datetime import datetime, timedelta, timezone

def handler(event, context):
    iam = boto3.client('iam')
    sns = boto3.client('sns')
    max_days = int(os.environ['MAX_UNUSED_DAYS'])
    
    revoked_keys = []
    
    # List all IAM users
    users = iam.list_users()['Users']
    
    for user in users:
        username = user['UserName']
        
        # Get access keys for this user
        keys = iam.list_access_keys(UserName=username)['AccessKeyMetadata']
        
        for key in keys:
            access_key_id = key['AccessKeyId']
            
            # Check last used date
            last_used = iam.get_access_key_last_used(
                AccessKeyId=access_key_id
            )['AccessKeyLastUsed']
            
            # If key has never been used or last used date exists
            if 'LastUsedDate' in last_used:
                days_unused = (datetime.now(timezone.utc) - last_used['LastUsedDate']).days
                
                if days_unused > max_days:
                    # Deactivate the key (don't delete — can be recovered)
                    iam.update_access_key(
                        UserName=username,
                        AccessKeyId=access_key_id,
                        Status='Inactive'
                    )
                    
                    revoked_keys.append({
                        'username': username,
                        'access_key_id': access_key_id,
                        'days_unused': days_unused
                    })
                    
                    print(f"Revoked key {access_key_id} for user {username} "
                          f"(unused for {days_unused} days)")
    
    # Send summary notification
    if revoked_keys:
        message = "Auto-remediation: Revoked unused IAM access keys:\n\n"
        for key in revoked_keys:
            message += f"  - User: {key['username']}\n"
            message += f"    Key: {key['access_key_id']}\n"
            message += f"    Days unused: {key['days_unused']}\n\n"
        
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Subject=f"REMEDIATED: {len(revoked_keys)} unused IAM keys revoked",
            Message=message
        )
    
    return {
        'statusCode': 200,
        'body': f'Revoked {len(revoked_keys)} unused IAM access keys'
    }
PYTHON
    filename = "index.py"
  }
}

# ============================================
# EventBridge Rules — Trigger remediation
# ============================================

# Rule: Trigger S3 remediation on public bucket detection
resource "aws_cloudwatch_event_rule" "public_s3_remediation" {
  name        = "ABSA-Public-S3-Remediation"
  description = "Triggers Lambda when a public S3 bucket is detected"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail_type = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = ["PutBucketAcl"]
      requestParameters = {
        AccessControlPolicy = {
          AccessControlList = {
            Grant = {
              Grantee = {
                URI = [
                  "http://acs.amazonaws.com/groups/global/AllUsers",
                  "http://acs.amazonaws.com/groups/global/AuthenticatedUsers"
                ]
              }
            }
          }
        }
      }
    }
  })

  tags = merge(local.common_tags, {
    Name = "ABSA-Public-S3-Remediation"
  })
}

resource "aws_cloudwatch_event_target" "public_s3_remediation" {
  rule      = aws_cloudwatch_event_rule.public_s3_remediation.name
  target_id = "TriggerBlockPublicS3"
  arn       = aws_lambda_function.block_public_s3.arn
}

# Permission: Allow EventBridge to invoke the remediation Lambda
resource "aws_lambda_permission" "block_public_s3" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.block_public_s3.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.public_s3_remediation.arn
}

# Rule: Trigger IAM remediation on schedule (daily)
resource "aws_cloudwatch_event_rule" "unused_iam_remediation" {
  name                = "ABSA-Unused-IAM-Remediation"
  description         = "Triggers Lambda daily to revoke unused IAM keys"
  schedule_expression = "rate(1 day)"

  tags = merge(local.common_tags, {
    Name = "ABSA-Unused-IAM-Remediation"
  })
}

resource "aws_cloudwatch_event_target" "unused_iam_remediation" {
  rule      = aws_cloudwatch_event_rule.unused_iam_remediation.name
  target_id = "TriggerRevokeUnusedIAM"
  arn       = aws_lambda_function.revoke_unused_iam.arn
}

resource "aws_lambda_permission" "revoke_unused_iam" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.revoke_unused_iam.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.unused_iam_remediation.arn
}