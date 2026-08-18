variable "region" {
  type    = string
  default = "ap-southeast-2"
}

variable "profile" {
  type    = string
  default = "dev-full"
}

variable "environment" {
  type    = string
  default = "development"
}

variable "environment_short" {
  type    = string
  default = "dev"
}

variable "name_prefix" {
  description = "Naming convention: k8s-demo-{env-short}"
  type        = string
  default     = "k8s-demo-dev"
}

variable "admin_principal_arn" {
  description = "IAM principal (user or role ARN) granted EKS cluster-admin access via an EKS access entry -- set this to whoever/whatever runs `terraform apply`."
  type        = string
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

variable "vpc_cidr" {
  type    = string
  default = "10.60.0.0/16"
}

variable "shared_account_id" {
  description = "AWS account ID of the shared environment, which owns the shared ECR repo dev pulls the deployed image from"
  type        = string
}

variable "create_oidc_provider" {
  description = "Whether this environment should create its own GitHub OIDC provider. Set to false to reuse an existing provider ARN from another module or account."
  type        = bool
  default     = false
}

variable "existing_oidc_provider_arn" {
  description = "ARN of the existing GitHub Actions OIDC provider to reuse in this AWS account. Set this when create_oidc_provider is false."
  type        = string
  default     = "arn:aws:iam::621508399429:oidc-provider/token.actions.githubusercontent.com"
}
