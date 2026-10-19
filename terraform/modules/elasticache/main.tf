# ElastiCache Subnet Group
resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.environment}-redis-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name        = "${var.environment}-redis-subnet-group"
    Environment = var.environment
  }
}

# ElastiCache Parameter Group
resource "aws_elasticache_parameter_group" "main" {
  name        = "${var.environment}-redis-params"
  family      = "redis7"
  description = "Parameter group for Redis 7"

  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }

  tags = {
    Name        = "${var.environment}-redis-params"
    Environment = var.environment
  }
}

# ElastiCache Cluster (using cluster mode for simpler configuration)
# NOTE: Encryption at rest (KMS) is only supported for replication groups,
# not for simple clusters. The redis_kms_key_arn variable is kept for
# future migration to replication group or for snapshot encryption.
resource "aws_elasticache_cluster" "main" {
  cluster_id           = "${var.environment}-job-scheduler-redis"
  engine               = "redis"
  engine_version       = var.engine_version
  node_type            = var.node_type
  num_cache_nodes      = var.num_cache_nodes
  port                 = 6379
  parameter_group_name = aws_elasticache_parameter_group.main.name
  subnet_group_name    = aws_elasticache_subnet_group.main.name
  security_group_ids   = var.redis_security_group_ids

  snapshot_retention_limit = var.environment == "prod" ? 7 : 1
  snapshot_window          = "03:00-04:00"
  maintenance_window       = "sun:04:00-sun:05:00"

  tags = {
    Name        = "${var.environment}-job-scheduler-redis"
    Environment = var.environment
  }
}

# NOTE: no auth token on purpose. aws_elasticache_cluster auth requires
# transit encryption (TLS), which the Go redis client is not configured for.
# Access control is via the redis security group (ECS tasks only) in private
# subnets. If auth is ever enabled, wire REDIS_PASSWORD into the task defs.

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "redis" {
  name              = "/aws/elasticache/${var.environment}/job-scheduler/redis"
  retention_in_days = var.environment == "prod" ? 30 : 7

  tags = {
    Name        = "${var.environment}-redis-logs"
    Environment = var.environment
  }
}