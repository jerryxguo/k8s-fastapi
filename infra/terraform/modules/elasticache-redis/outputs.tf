output "primary_endpoint_address" {
  value = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "secret_name" {
  description = "Secrets Manager secret holding APP_REDIS_URL; referenced by the Helm chart's externalSecret.redisSecretName."
  value       = aws_secretsmanager_secret.redis.name
}

output "security_group_id" {
  value = aws_security_group.this.id
}
