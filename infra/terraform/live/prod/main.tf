locals {
  cluster_name = "${var.name_prefix}-eks"
  tags = {
    NamePrefix = var.name_prefix
  }
}

module "vpc" {
  source = "../../modules/vpc"

  name_prefix  = var.name_prefix
  cluster_name = local.cluster_name
  vpc_cidr     = var.vpc_cidr

  # Prod gets one NAT gateway per AZ for resilience, unlike dev's single
  # shared NAT gateway.
  single_nat_gateway = false

  tags = local.tags
}

# No ECR module here: the "shared" environment owns the single shared repo
# and grants this account cross-account pull (see
# infra/terraform/live/shared/main.tf's pull_account_ids) -- the same image
# digest built and pushed there is what gets deployed straight to
# production.
locals {
  ecr_repository_arn = "arn:aws:ecr:${var.region}:${var.shared_account_id}:repository/k8s-demo-shared/service-api"
}

module "eks" {
  source = "../../modules/eks-cluster"

  cluster_name        = local.cluster_name
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  admin_principal_arn = var.admin_principal_arn
  cicd_role_arn       = module.cicd_role.role_arn

  node_min_size     = 3
  node_max_size     = 6
  node_desired_size = 3

  tags = local.tags
}

module "cicd_role" {
  source = "../../modules/github-oidc-cicd-role"

  name_prefix                 = var.name_prefix
  github_org                  = var.github_org
  github_repo                 = var.github_repo
  github_owner_id             = var.github_owner_id
  github_repository_id        = var.github_repository_id
  github_environment          = "production"
  grant_ecr_push              = false # prod only deploys; "shared" owns push access
  create_oidc_provider       = var.create_oidc_provider
  existing_oidc_provider_arn = var.existing_oidc_provider_arn
  tags                       = local.tags
}

resource "aws_secretsmanager_secret" "app" {
  name = "${var.name_prefix}/app-config"
  tags = local.tags
}

module "app_irsa" {
  source = "../../modules/irsa-role"

  name_prefix          = var.name_prefix
  oidc_provider_arn    = module.eks.oidc_provider_arn
  oidc_provider_url    = module.eks.oidc_provider_url
  namespace            = "k8s-demo"
  service_account_name = "k8s-demo-service"

  inline_policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadOwnSecret"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [aws_secretsmanager_secret.app.arn]
      }
    ]
  })

  tags = local.tags
}

module "external_secrets_irsa" {
  source = "../../modules/irsa-role"

  name_prefix          = var.name_prefix
  oidc_provider_arn    = module.eks.oidc_provider_arn
  oidc_provider_url    = module.eks.oidc_provider_url
  namespace            = "external-secrets"
  service_account_name = "external-secrets"

  inline_policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadEnvironmentSecrets"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = ["arn:aws:secretsmanager:${var.region}:*:secret:${var.name_prefix}/*"]
      }
    ]
  })

  tags = local.tags
}
