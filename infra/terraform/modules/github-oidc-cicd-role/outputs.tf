output "role_arn" {
  value = aws_iam_role.cicd.arn
}

output "oidc_provider_arn" {
  value = local.oidc_provider_arn
}
