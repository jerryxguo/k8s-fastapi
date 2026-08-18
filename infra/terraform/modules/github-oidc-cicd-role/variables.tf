variable "name_prefix" {
  type = string
}

variable "github_org" {
  type    = string
  default = "your-org"
}

variable "github_repo" {
  type    = string
  default = "K8s"
}

variable "github_environment" {
  description = "GitHub Environment name this role trusts (e.g. development/production). Set to null and use github_ref_branch instead for branch-scoped trust."
  type        = string
  default     = null
}

variable "github_ref_branch" {
  description = "Branch to trust when github_environment is null (e.g. main)"
  type        = string
  default     = "main"
}

variable "ecr_repository_arn" {
  description = "ARN of the ECR repo to grant push access to. Required only when grant_ecr_push is true."
  type        = string
  default     = null
}

variable "grant_ecr_push" {
  description = "Whether this role can push images (true for the environment that owns the shared ECR repo; false for environments that only pull cross-account and deploy)."
  type        = bool
  default     = true
}

variable "create_oidc_provider" {
  description = "Whether to create the account's GitHub Actions OIDC provider. There can only be one per AWS account -- set false and pass existing_oidc_provider_arn for every environment after the first if all environments share an account."
  type        = bool
  default     = true
}

variable "existing_oidc_provider_arn" {
  type    = string
  default = null
}

variable "github_owner_id" {
  description = "Immutable numeric ID of the GitHub org/user that owns this repo. GitHub started issuing OIDC tokens with immutable subject claims (repo:org@ownerID/repo@repoID:...) by default for repositories created after 2026-07-15 (and this can be opted into for older repos too) -- see docs.github.com/actions/reference/openid-connect-reference. Set this (and github_repository_id) to match whatever your actual token issues, or the trust policy's sub condition will never match and AssumeRoleWithWebIdentity fails with a generic 'Not authorized' error that gives no hint this is the cause. Find via: gh api repos/<owner>/<repo> --jq '.owner.id'. Leave null to use the legacy plain-name subject format."
  type        = string
  default     = null
}

variable "github_repository_id" {
  description = "Immutable numeric ID of this GitHub repository. See github_owner_id for why this matters. Find via: gh api repos/<owner>/<repo> --jq '.id'."
  type        = string
  default     = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
