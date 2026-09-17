# Module: secrets
# Non-RDS application secrets in Secrets Manager. RDS master credentials are
# owned by the rds module (PETPLAT-23) and are NOT duplicated here.
#
# Implements PETPLAT-33. See docs/technical-spec.md#secrets-management.

locals {
  name_prefix = "${var.project}-${var.environment}"
}

# count-gated: genai-service is optional (docs/technical-spec.md#application-services).
# AWS Secrets Manager rejects an empty SecretString, so an empty
# var.openai_api_key skips the secret entirely instead of storing a
# placeholder — set a real key to create it.
resource "aws_secretsmanager_secret" "openai_api_key" {
  count       = var.openai_api_key != "" ? 1 : 0
  name        = "${var.project}/${var.environment}/openai-api-key"
  description = "OpenAI API key for ${local.name_prefix}-genai-service."

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-openai-api-key"
  })
}

# secret_string carries var.openai_api_key's sensitive mark through to this
# resource's attributes, so the value is redacted from plan/apply CLI output
# and `terraform show` (same mechanism as the rds module's master password).
resource "aws_secretsmanager_secret_version" "openai_api_key" {
  count         = var.openai_api_key != "" ? 1 : 0
  secret_id     = aws_secretsmanager_secret.openai_api_key[0].id
  secret_string = var.openai_api_key
}
