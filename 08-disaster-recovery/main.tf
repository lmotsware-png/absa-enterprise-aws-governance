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
    key            = "08-disaster-recovery/terraform.tfstate"
    region         = "af-south-1"
    dynamodb_table = "absa-terraform-locks"
    encrypt        = true
  }
}

# Read outputs from Weeks 1-7
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

data "terraform_remote_state" "shared_services" {
  backend = "s3"
  config = {
    bucket = "absa-terraform-state-af-south-1"
    key    = "04-shared-services/terraform.tfstate"
    region = "af-south-1"
  }
}