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

  validation {
    # main.tf's layout reserves netnums 0-7 private, 8-15 public.
    condition     = length(var.azs) > 0 && length(var.azs) <= 8
    error_message = "azs must contain between 1 and 8 availability zones."
  }
}

variable "private_subnet_cidrs" {
  description = "Explicit private subnet CIDRs. Leave null (the default) to derive them from vpc_cidr -- see the locals block in main.tf. Only set this to carve up the VPC by hand."
  type        = list(string)
  default     = null
}

variable "public_subnet_cidrs" {
  description = "Explicit public subnet CIDRs. Leave null (the default) to derive them from vpc_cidr -- see the locals block in main.tf. Only set this to carve up the VPC by hand."
  type        = list(string)
  default     = null
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
