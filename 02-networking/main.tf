terraform {
  required_version = ">= 1.8.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.22.0"
    }
  }
# Pull outputs from Week 1's governance stack for use in this networking stack
  backend "s3" {
    bucket         = "absa-terraform-state-eu-west-1"
    key            = "02-networking/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "absa-terraform-locks"
    encrypt        = true
  }
}
# Reference Week 1's outputs for use in this stack
data "terraform_remote_state" "governance" {
  backend = "s3"
  config = {
    bucket = "absa-terraform-state-eu-west-1"
    key    = "01-governance/terraform.tfstate"
    region = "eu-west-1"
  }
}

provider "aws" {
  region = var.primary_region

  default_tags {
    tags = {
      Environment = "Production"
      Project     = "ABSA-Enterprise-AWS"
      ManagedBy   = "Terraform"
      Week        = "02-Networking"
    }
  }
}
# Provider for DR region 
provider "aws" {
  alias  = "dr"
  region = var.dr_region

  default_tags {
    tags = {
      Environment = "Production"
      Project     = "ABSA-Enterprise-AWS"
      ManagedBy   = "Terraform"
      Week        = "02-Networking"
    }
  }
}