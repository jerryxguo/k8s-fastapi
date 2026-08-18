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
  description = "Repo name as it appears in the GitHub URL (github.com/<org>/<repo>) -- only change this if the repo isn't actually named \"K8s\"."
  type        = string
  default     = "K8s"
}

variable "dev_account_id" {
  description = "AWS account ID of the dev environment, granted cross-account ECR pull"
  type        = string
}

variable "prod_account_id" {
  description = "AWS account ID of the production environment, granted cross-account ECR pull"
  type        = string
}
