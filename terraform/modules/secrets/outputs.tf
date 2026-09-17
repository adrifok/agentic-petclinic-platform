# Module: secrets — outputs
# See docs/technical-spec.md#terraform-modules.

output "openai_secret_arn" {
  description = "Secrets Manager ARN for the OpenAI API key (for External Secrets Operator — PETPLAT-36), or null while genai-service is skipped."
  value       = try(aws_secretsmanager_secret.openai_api_key[0].arn, null)
}

output "openai_secret_name" {
  description = "Secrets Manager secret name for the OpenAI API key (petclinic/{env}/openai-api-key), or null while genai-service is skipped."
  value       = try(aws_secretsmanager_secret.openai_api_key[0].name, null)
}
