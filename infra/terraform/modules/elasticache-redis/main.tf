# ElastiCache Redis used as the Celery broker: the API enqueues task payloads
# here and the Celery worker Deployment consumes them (src/app/worker.py).
#
# Private subnets only, reachable only from EKS nodes (pods use the node's
# security group under the VPC CNI), TLS in transit, encrypted at rest, and
# an AUTH token. The full connection URL is written to Secrets Manager, so it
# reaches pods the same way every other secret does (External Secrets
# Operator -> Kubernetes Secret -> APP_REDIS_URL env var) -- no AWS SDK or
# IAM permissions needed in the app.

resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.name_prefix}-redis"
  subnet_ids = var.subnet_ids
  tags       = var.tags
}

resource "aws_security_group" "this" {
  name        = "${var.name_prefix}-redis"
  description = "Celery broker Redis; ingress from EKS nodes only"
  vpc_id      = var.vpc_id
  tags        = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "from_nodes" {
  for_each = { for idx, sg in var.allowed_security_group_ids : idx => sg }

  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  description                  = "Redis from EKS nodes/pods"
}

# A broker must never silently drop data. ElastiCache's default policy
# (volatile-lru) can evict keys under memory pressure -- including Celery's
# unacked-task bookkeeping, which carries TTLs -- losing tasks with no error.
# noeviction makes a full broker fail loudly on enqueue instead (the API
# returns 503 and the scanner retries).
resource "aws_elasticache_parameter_group" "this" {
  name   = "${var.name_prefix}-redis7-broker"
  family = "redis7"

  parameter {
    name  = "maxmemory-policy"
    value = "noeviction"
  }

  tags = var.tags
}

# Alphanumeric only: ElastiCache rejects some punctuation in AUTH tokens, and
# it keeps the token URL-safe inside APP_REDIS_URL without encoding.
resource "random_password" "auth_token" {
  length  = 64
  special = false
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${var.name_prefix}-redis"
  description          = "Celery broker for ${var.name_prefix}"

  engine               = "redis"
  engine_version       = var.engine_version
  node_type            = var.node_type
  port                 = 6379
  parameter_group_name = aws_elasticache_parameter_group.this.name

  # >1 node gives a replica in another AZ plus automatic failover; the app
  # always connects to the primary endpoint, which follows the failover.
  num_cache_clusters         = var.num_cache_clusters
  automatic_failover_enabled = var.num_cache_clusters > 1
  multi_az_enabled           = var.num_cache_clusters > 1

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.this.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = random_password.auth_token.result

  # Daily snapshots so queued-but-unprocessed tasks survive a total cluster
  # loss (0 disables, e.g. in dev).
  snapshot_retention_limit = var.snapshot_retention_limit

  apply_immediately = var.apply_immediately
  tags              = var.tags
}

resource "aws_secretsmanager_secret" "redis" {
  name                    = "${var.name_prefix}/redis"
  description             = "Celery broker connection URL (APP_REDIS_URL), managed by Terraform"
  recovery_window_in_days = var.secret_recovery_window_days
  tags                    = var.tags
}

# Terraform owns this value (unlike the app-config secret, which humans
# populate): rotating the token here updates the secret, and ESO picks it up
# on its next refresh. Pods read env vars only at start, so restart the API
# and worker Deployments after a rotation.
resource "aws_secretsmanager_secret_version" "redis" {
  secret_id = aws_secretsmanager_secret.redis.id
  secret_string = jsonencode({
    # rediss:// = TLS. The key name becomes the env var name via ESO's
    # dataFrom.extract.
    APP_REDIS_URL = "rediss://:${random_password.auth_token.result}@${aws_elasticache_replication_group.this.primary_endpoint_address}:6379/0"
  })
}
