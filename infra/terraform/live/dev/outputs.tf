output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "ecr_repository_arn" {
  value = local.ecr_repository_arn
}

output "cicd_role_arn" {
  value = module.cicd_role.role_arn
}

output "app_irsa_role_arn" {
  value = module.app_irsa.role_arn
}

output "redis_primary_endpoint" {
  value = module.redis.primary_endpoint_address
}

output "redis_secret_name" {
  value = module.redis.secret_name
}

output "external_secrets_irsa_role_arn" {
  value = module.external_secrets_irsa.role_arn
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
}
