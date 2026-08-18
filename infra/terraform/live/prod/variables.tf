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
  description = "Your actual GitHub org or username that owns this repo () -- required, no default. This feeds the cicd_role module's OIDC trust condition (sub == \"repo:${github_org}/${github_repo}:environment:production\"); leaving this at a placeholder value makes the IAM role trust a subject that GitHub's real OIDC token will never present, which surfaces later as an opaque \"Not authorized to perform sts:AssumeRoleWithWebIdentity\" in CI instead of failing here at plan time."
  type        = string
}

variable "github_repo" {
  description = "Repo name as it appears in the GitHub URL (github.com/<org>/<repo>) -- only change this if the repo isn't actually named \"K8s\"."
  type        = string
  default     = "K8s"
}

variable "vpc_cidr" {
  type    = string
  default = "10.62.0.0/16"
}

variable "shared_account_id" {
  description = "AWS account ID of the shared environment, which owns the shared ECR repo prod pulls the deployed image from"
  type        = string
}
