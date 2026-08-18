variable "name_prefix" {
  type = string
}

variable "repository_name" {
  type    = string
  default = "service-api"
}

variable "pull_account_ids" {
  description = "Other AWS account IDs allowed to pull this image (e.g. the prod account pulling from a shared build account). Empty by default."
  type        = list(string)
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
