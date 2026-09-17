# Module: secrets — outputs
# See docs/technical-spec.md#terraform-modules.

output "openai_secret_arn" {
  description = "Secrets Manager ARN for the OpenAI API key (for External Secrets Operator — PETPLAT-36)."
  value       = aws_secretsmanager_secret.openai_api_key.arn
}

output "openai_secret_name" {
  description = "Secrets Manager secret name for the OpenAI API key (petclinic/{env}/openai-api-key)."
  value       = aws_secretsmanager_secret.openai_api_key.name
}
