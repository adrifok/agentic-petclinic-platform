# Module: secrets
# Non-RDS application secrets in Secrets Manager. RDS master credentials are
# owned by the rds module (PETPLAT-23) and are NOT duplicated here.
#
# Implements PETPLAT-33. See docs/technical-spec.md#secrets-management.

locals {
  name_prefix = "${var.project}-${var.environment}"
}

resource "aws_secretsmanager_secret" "openai_api_key" {
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
  secret_id     = aws_secretsmanager_secret.openai_api_key.id
  secret_string = var.openai_api_key
}
