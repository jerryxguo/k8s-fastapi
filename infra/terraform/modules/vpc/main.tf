# Thin wrapper around the well-audited terraform-aws-modules/vpc/aws
# registry module. EKS needs its own properly-tagged subnets (for the AWS
# Load Balancer Controller and any node-group autoscaling), so a dedicated
# VPC is provisioned per environment here.
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"

  name = "${var.name_prefix}-vpc"
  cidr = var.vpc_cidr

  azs             = var.azs
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

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
    "kubernetes.io/role/elb"                     = "1"
    "kubernetes.io/cluster/${var.cluster_name}"  = "shared"
  })
  private_subnet_tags = merge(var.tags, {
    "kubernetes.io/role/internal-elb"            = "1"
    "kubernetes.io/cluster/${var.cluster_name}"  = "shared"
  })

  tags = var.tags
}
