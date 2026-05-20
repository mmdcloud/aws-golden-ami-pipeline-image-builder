terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
  backend "s3" {
    bucket         = "tfstate-ami-factory"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "tfstate-ami-factory-lock"
  }
}

provider "aws" {
  region = var.primary_region
  default_tags {
    tags = {
      Environment = "Production"
      Project     = "AMI Factory"
      ManagedBy   = "Terraform"
    }
  }
}

provider "aws" {
  alias  = "eu_west"
  region = "eu-west-1"
  default_tags {
    tags = {
      Environment = "Production"
      Project     = "AMI Factory"
      ManagedBy   = "Terraform"
    }
  }
}

provider "aws" {
  alias  = "ap_southeast"
  region = "ap-southeast-1"
  default_tags {
    tags = {
      Environment = "Production"
      Project     = "AMI Factory"
      ManagedBy   = "Terraform"
    }
  }
}