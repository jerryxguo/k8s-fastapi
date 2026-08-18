variable "name_prefix" {
  description = "Naming prefix, e.g. k8s-demo-dev ({platform}-{service}-{env} convention)"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name these subnets will be tagged for"
  type        = string
}

variable "vpc_cidr" {
  type    = string
  default = "10.60.0.0/16"
}

variable "azs" {
  type    = list(string)
  default = ["ap-southeast-2a", "ap-southeast-2b"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.60.0.0/20", "10.60.16.0/20"]
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.60.128.0/20", "10.60.144.0/20"]
}

variable "single_nat_gateway" {
  description = "Use one shared NAT gateway instead of one per AZ (cheaper, less resilient -- fine for dev)"
  type        = bool
  default     = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
