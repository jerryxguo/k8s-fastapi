locals {
  tags = {
    NamePrefix = var.name_prefix
  }
}

# This environment exists for exactly one reason: own the single ECR repo
# every other environment pulls the same image from, and the one GitHub
# OIDC role allowed to push to it. Nothing runs here -- no VPC, no EKS
# cluster, no app -- so there's nothing else in this file. See
# docs/DESIGN-NOTES.md's "ECR strategy".
module "ecr" {
  source = "../../modules/ecr-repo"

  name_prefix      = "k8s-demo-shared"
  repository_name  = "service-api"
  pull_account_ids = [var.dev_account_id, var.prod_account_id]
  tags             = local.tags
}

module "cicd_role" {
  source = "../../modules/github-oidc-cicd-role"

  name_prefix           = var.name_prefix
  github_org            = var.github_org
  github_repo           = var.github_repo
  github_owner_id       = var.github_owner_id
  github_repository_id  = var.github_repository_id
  github_environment    = "shared"
  ecr_repository_arn    = module.ecr.repository_arn
  grant_ecr_push        = true # the one environment that builds + pushes the image
  create_oidc_provider  = true # only true in exactly one environment per AWS account
  tags                  = local.tags
}
