variable "region" {
  type    = string
  default = "ap-southeast-2"
}

variable "profile" {
  type    = string
  default = "shared-full"
}

variable "environment" {
  type    = string
  default = "shared"
}

variable "name_prefix" {
  type    = string
  default = "k8s-demo-shared"
}

variable "github_org" {
  description = "Your actual GitHub org or username"
  type        = string
}

variable "github_repo" {
  description = "Repo name as it appears in the GitHub URL (github.com/<org>/<repo>)."
  type        = string
  default     = "k8s-fastapi"
}

variable "dev_account_id" {
  description = "AWS account ID of the dev environment, granted cross-account ECR pull"
  type        = string
}

variable "prod_account_id" {
  description = "AWS account ID of the production environment, granted cross-account ECR pull"
  type        = string
}

# GitHub now issues OIDC tokens with immutable subject claims (owner/repo
# numeric IDs baked in) by default for repos created after 2026-07-15 --
# see modules/github-oidc-cicd-role/variables.tf for why this matters.
# Find current values via: gh api repos/<owner>/<repo> --jq '.owner.id,.id'
variable "github_owner_id" {
  type    = string
  default = "10950337"
}

variable "github_repository_id" {
  type    = string
  default = "1337888631"
}
