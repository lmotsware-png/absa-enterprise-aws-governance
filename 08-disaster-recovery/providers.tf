# ============================================
# AWS Providers — Week 8 Disaster Recovery
# Three providers: primary, DR, and us-east-1 for CloudFront ACM
# ============================================

# Primary region — af-south-1 (Cape Town)
provider "aws" {
  region = var.primary_region

  default_tags {
    tags = {
      Environment = "Production"
      Project     = "ABSA-Enterprise-AWS"
      ManagedBy   = "Terraform"
      Week        = "08-Disaster-Recovery"
    }
  }
}

# DR region — eu-west-1 (Ireland)
provider "aws" {
  alias  = "dr"
  region = var.dr_region

  default_tags {
    tags = {
      Environment = "Production"
      Project     = "ABSA-Enterprise-AWS"
      ManagedBy   = "Terraform"
      Week        = "08-Disaster-Recovery"
    }
  }
}

# us-east-1 — Required for CloudFront ACM certificates
# AWS enforces: CloudFront certificates must be in us-east-1
# regardless of where the origin lives
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Environment = "Production"
      Project     = "ABSA-Enterprise-AWS"
      ManagedBy   = "Terraform"
      Week        = "08-Disaster-Recovery"
    }
  }
}