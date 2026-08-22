locals {
  common_tags = {
    Project     = "ABSA-Enterprise-AWS"
    CostCenter  = "Cloud-Security"
    DataClass   = "Confidential"
    ManagedBy   = "Terraform"
  }

  kms_aliases = {
    rds         = "alias/absa-rds-encryption"
    s3          = "alias/absa-s3-encryption"
    secrets     = "alias/absa-secrets-encryption"
    lambda      = "alias/absa-lambda-encryption"
    cloudtrail  = "alias/absa-cloudtrail-encryption"
    eks         = "alias/absa-eks-secrets"
    ebs         = "alias/absa-ebs-encryption" 
  }

  iam_roles = {
    eks_cluster     = "ABSA-EKS-Cluster-Role"
    eks_node        = "ABSA-EKS-Node-Role"
    lambda_exec     = "ABSA-Lambda-Execution-Role"
    secrets_manager = "ABSA-Secrets-Manager-Role"
    cloudtrail      = "ABSA-CloudTrail-Role"
    config          = "ABSA-Config-Role"
  }

  secrets = {
    rds_master_password = {
      description = "Master password for RDS Aurora cluster"
      secret_type = "SecureString"
    }
    api_gateway_key = {
      description = "API Gateway client secret"
      secret_type = "SecureString"
    }
    redis_auth_token = {
      description = "ElastiCache Redis authentication token"
      secret_type = "SecureString"
    }
   
  }

  remediation_events = {
    public_s3 = {
      event_pattern = "AWS API Call via CloudTrail: PutBucketAcl with public-read"
      target_key    = "block_public_s3"
    }
    unused_iam = {
      event_pattern = "IAM Access Key older than 90 days detected"
      target_key    = "revoke_unused_iam"
    }
  }
}
