variable "name_prefix" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "oidc_provider_url" {
  description = "OIDC provider URL without the https:// scheme, e.g. oidc.eks.ap-southeast-2.amazonaws.com/id/XXXX"
  type        = string
}

variable "namespace" {
  type = string
}

variable "service_account_name" {
  type = string
}

variable "managed_policy_arns" {
  type    = list(string)
  default = []
}

variable "inline_policy_json" {
  type    = string
  default = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
