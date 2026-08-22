terraform {
  required_version = ">= 1.8.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.22.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
  }

  backend "s3" {
    bucket         = "absa-terraform-state-af-south-1"
    key            = "05-production/terraform.tfstate"   # ← FIXED
    region         = "af-south-1"
    dynamodb_table = "absa-terraform-locks"
    encrypt        = true
  }
}

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

provider "aws" {
  region = var.primary_region

  default_tags {
    tags = {
      Environment = "Production"
      Project     = "ABSA-Enterprise-AWS"
      ManagedBy   = "Terraform"
      Week        = "05-Production"   # ← FIXED
    }
  }
}

data "aws_eks_cluster" "main" {
  name = aws_eks_cluster.main.name
}

data "aws_eks_cluster_auth" "main" {
  name = aws_eks_cluster.main.name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.main.token
}