# Thin wrapper around the well-audited terraform-aws-modules/vpc/aws
# registry module. EKS needs its own properly-tagged subnets (for the AWS
# Load Balancer Controller and any node-group autoscaling), so a dedicated
# VPC is provisioned per environment here.
locals {
  # Derived from vpc_cidr, never defaulted independently: a caller that
  # overrides only vpc_cidr would otherwise get subnets outside its own VPC,
  # which fails at apply (InvalidSubnet.Range), not at plan. For a /16, 4
  # newbits gives sixteen /20s; private takes 0..n-1, public starts at 8 so
  # either range can grow without renumbering the other.
  private_subnet_cidrs = var.private_subnet_cidrs != null ? var.private_subnet_cidrs : [for idx, az in var.azs : cidrsubnet(var.vpc_cidr, 4, idx)]
  public_subnet_cidrs  = var.public_subnet_cidrs != null ? var.public_subnet_cidrs : [for idx, az in var.azs : cidrsubnet(var.vpc_cidr, 4, idx + 8)]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"

  name = "${var.name_prefix}-vpc"
  cidr = var.vpc_cidr

  azs             = var.azs
  private_subnets = local.private_subnet_cidrs
  public_subnets  = local.public_subnet_cidrs

  enable_nat_gateway     = true
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = !var.single_nat_gateway

  enable_dns_hostnames = true
  enable_dns_support   = true

  # Required so the AWS Load Balancer Controller and EKS's own subnet
  # auto-discovery can find the right subnets for internet-facing vs.
  # internal load balancers, and so a cluster autoscaler / Karpenter can
  # discover which subnets belong to which cluster.
  public_subnet_tags = merge(var.tags, {
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })
  private_subnet_tags = merge(var.tags, {
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })

  tags = var.tags
}
