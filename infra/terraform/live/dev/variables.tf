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
  description = "Repo name as it appears in the GitHub URL (github.com/<org>/<repo>) -- only change this if the repo isn't actually named \"K8s\"."
  type        = string
  default     = "K8s"
}

variable "vpc_cidr" {
  type    = string
  default = "10.60.0.0/16"
}

variable "shared_account_id" {
  description = "AWS account ID of the shared environment, which owns the shared ECR repo dev pulls the deployed image from"
  type        = string
}
