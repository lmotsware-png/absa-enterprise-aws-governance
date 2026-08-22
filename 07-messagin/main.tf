terraform {
  required_version = ">= 1.8.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.22.0"
    }
  }

  backend "s3" {
    bucket         = "absa-terraform-state-af-south-1"
    key            = "07-messaging/terraform.tfstate"
    region         = "af-south-1"
    dynamodb_table = "absa-terraform-locks"
    encrypt        = true
  }
}

# Read outputs from Weeks 1-6
data "terraform_remote_state" "governance" {
  backend = "s3"
  config = {
    bucket = "absa-terraform-state-af-south-1"
    key    = "01-governance/terraform.tfstate"
    region = "af-south-1"
  }
}

data "terraform_remote_state" "networking" {
  backend = "s3"
  config = {
    bucket = "absa-terraform-state-af-south-1"
    key    = "02-networking/terraform.tfstate"
    region = "af-south-1"
  }
}

data "terraform_remote_state" "security" {
  backend = "s3"
  config = {
    bucket = "absa-terraform-state-af-south-1"
    key    = "03-security/terraform.tfstate"
    region = "af-south-1"
  }
}

data "terraform_remote_state" "production" {
  backend = "s3"
  config = {
    bucket = "absa-terraform-state-af-south-1"
    key    = "05-production/terraform.tfstate"
    region = "af-south-1"
  }
}

data "terraform_remote_state" "data_platform" {
  backend = "s3"
  config = {
    bucket = "absa-terraform-state-af-south-1"
    key    = "06-data-platform/terraform.tfstate"
    region = "af-south-1"
  }
}

provider "aws" {
  region = var.primary_region

  default_tags {
    tags = {
      Environment = "Production"
      Project     = "ABSA-Enterprise-AWS"
      ManagedBy   = "Terraform"
      Week        = "07-Messaging"
    }
  }
}