variable "region" {
  type    = string
  default = "ap-southeast-2"
}

variable "profile" {
  type    = string
  default = "prod-full"
}

variable "environment" {
  type    = string
  default = "production"
}

variable "environment_short" {
  type    = string
  default = "prod"
}

variable "name_prefix" {
  type    = string
  default = "k8s-demo-prod"
}

variable "admin_principal_arn" {
  description = "IAM principal (user or role ARN) granted EKS cluster-admin access via an EKS access entry -- set this to whoever/whatever runs `terraform apply` in the production account."
  type        = string
}

variable "github_org" {
  description = "Your actual GitHub org or username that owns this repo. This feeds the cicd_role module's OIDC trust condition for the production environment."
  type        = string
}

variable "github_repo" {
  description = "Repo name as it appears in the GitHub URL (github.com/<org>/<repo>)."
  type        = string
  default     = "k8s-fastapi"
}

variable "vpc_cidr" {
  type    = string
  default = "10.62.0.0/16"
}

variable "shared_account_id" {
  description = "AWS account ID of the shared environment, which owns the shared ECR repo prod pulls the deployed image from"
  type        = string
}

variable "create_oidc_provider" {
  description = "Whether this environment should create its own GitHub OIDC provider. Set to false to reuse an existing provider ARN from another module or account."
  type        = bool
  default     = true
}

variable "existing_oidc_provider_arn" {
  description = "ARN of the existing GitHub Actions OIDC provider to reuse in this AWS account. Set this when create_oidc_provider is false."
  type        = string
  default     = null
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

variable "secret_recovery_window_days" {
  description = "Secrets Manager soft-delete window for the app secret. Real recovery window; never 0 here."
  type        = number
  default     = 30
}
