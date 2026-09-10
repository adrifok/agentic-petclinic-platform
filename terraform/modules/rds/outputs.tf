# Module: rds — outputs
# See docs/technical-spec.md#terraform-modules.

output "endpoint" {
  description = "RDS endpoint hostname (no port — see the port output; concatenate as {endpoint}:{port} for the JDBC URL)."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "RDS port (3306)."
  value       = aws_db_instance.this.port
}

output "db_instance_id" {
  description = "RDS instance ID."
  value       = aws_db_instance.this.id
}

output "db_name" {
  description = "Shared database name (petclinic)."
  value       = aws_db_instance.this.db_name
}

output "secret_arn" {
  description = "Secrets Manager secret ARN for RDS credentials (for External Secrets Operator — PETPLAT-35)."
  value       = aws_secretsmanager_secret.rds_credentials.arn
}

output "secret_name" {
  description = "Secrets Manager secret name for RDS credentials (petclinic/{env}/rds-credentials)."
  value       = aws_secretsmanager_secret.rds_credentials.name
}

output "error_log_group_name" {
  description = "CloudWatch log group name for the RDS error log export."
  value       = aws_cloudwatch_log_group.rds_error.name
}
