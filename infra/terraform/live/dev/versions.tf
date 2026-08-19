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
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.33"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.16"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
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

# Both kubernetes and helm authenticate against the cluster this same
# environment just created (module.eks), via the same identity Terraform
# itself is running as (var.profile) -- rather than a separate kubeconfig
# file, so there's nothing extra to keep in sync. This is the standard,
# widely-used pattern for bootstrapping cluster-internal resources
# (namespaces, operators, CRs) in the same apply that creates the cluster;
# the one known rough edge is a fresh cluster's very first apply, where
# Terraform may need to run twice -- see the comment on
# kubernetes_manifest.cluster_secret_store in main.tf for why.
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region, "--profile", var.profile]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region, "--profile", var.profile]
    }
  }
}
