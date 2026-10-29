variable "name_prefix" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Private subnets for the cache nodes."
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Security groups allowed to connect on 6379 -- the EKS node security group."
  type        = list(string)
}

variable "engine_version" {
  type    = string
  default = "7.1"
}

variable "node_type" {
  type    = string
  default = "cache.t4g.micro"
}

variable "num_cache_clusters" {
  description = "1 = single node (no failover). 2+ = primary + replicas across AZs with automatic failover."
  type        = number
  default     = 1
}

variable "snapshot_retention_limit" {
  description = "Days of daily snapshots to keep; 0 disables."
  type        = number
  default     = 0
}

variable "apply_immediately" {
  description = "Apply modifications now rather than in the next maintenance window."
  type        = bool
  default     = false
}

variable "secret_recovery_window_days" {
  description = "Secrets Manager soft-delete window for the connection-URL secret."
  type        = number
  default     = 30
}

variable "tags" {
  type    = map(string)
  default = {}
}
