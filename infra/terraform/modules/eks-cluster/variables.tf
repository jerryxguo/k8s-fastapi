variable "cluster_name" {
  type = string
}

variable "kubernetes_version" {
  description = "EKS cluster Kubernetes version. Keep this on a version AWS currently has on standard support -- old versions stop getting new node-group AMIs published once their extended support window ends, which breaks `terraform apply` with \"Requested AMI for this version is not supported\" even though nothing in this config changed. Check https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions-standard.html before bumping. NOTE: the one-minor-version-at-a-time rule only applies to *upgrading* an existing cluster (UpdateClusterVersion) -- it's not a constraint on cluster creation. If you're destroying and recreating rather than upgrading in place, you can jump straight to any currently-supported version."
  type        = string
  default     = "1.36"
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "admin_principal_arn" {
  description = "IAM principal (e.g. the Terraform deployer's role/user) granted cluster-admin access"
  type        = string
}

variable "cicd_role_arn" {
  description = "IAM role ARN used by the GitHub Actions deploy job; granted cluster-admin via the access entry in main.tf so it can helm/kubectl apply (see the DECISION comment there for why cluster-admin rather than a narrower policy). Required (no default) -- every caller of this module is expected to have a CI/CD role to pass in. It's fine for this to be an apply-time-unknown value (e.g. a role created in the same apply); see the comment on `access_entries` in main.tf for why that's safe here but wasn't safe when this was gated by an optional/nullable variable."
  type        = string
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 3
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "node_capacity_type" {
  type    = string
  default = "ON_DEMAND"
}

variable "tags" {
  type    = map(string)
  default = {}
}
