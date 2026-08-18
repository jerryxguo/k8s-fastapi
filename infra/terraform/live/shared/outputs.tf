output "ecr_repository_url" {
  value = module.ecr.repository_url
}

output "ecr_repository_arn" {
  value = module.ecr.repository_arn
}

output "cicd_role_arn" {
  value = module.cicd_role.role_arn
}
