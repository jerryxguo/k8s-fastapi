terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.region
  profile = var.profile

  default_tags {
    tags = {
      Project     = "k8s-demo-service"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
