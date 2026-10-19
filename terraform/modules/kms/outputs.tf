output "rds_kms_key_arn" {
  value       = aws_kms_key.rds.arn
  description = "RDS KMS key ARN"
}

output "redis_kms_key_arn" {
  value       = aws_kms_key.redis.arn
  description = "Redis KMS key ARN"
}