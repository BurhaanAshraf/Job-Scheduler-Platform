output "redis_endpoint" {
  value       = aws_elasticache_cluster.main.cache_nodes[0].address
  description = "Primary Redis endpoint"
  sensitive   = true
}

output "redis_port" {
  value       = aws_elasticache_cluster.main.cache_nodes[0].port
  description = "Redis port"
}

output "redis_cluster_id" {
  value       = aws_elasticache_cluster.main.cluster_id
  description = "Redis cluster ID"
}