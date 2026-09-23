# Module: secrets — input variables
# See docs/technical-spec.md#secrets-management and #terraform-modules.

variable "project" {
  description = "Project name, used in resource naming."
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Deployment environment (dev or prod)."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be \"dev\" or \"prod\"."
  }
}

variable "openai_api_key" {
  description = "OpenAI API key for genai-service, stored in Secrets Manager as petclinic/{env}/openai-api-key. Never hardcode — pass via terraform.tfvars (gitignored) or TF_VAR_openai_api_key. genai-service is optional (see docs/technical-spec.md#application-services) — defaults to empty until a real key is set."
  type        = string
  sensitive   = true
  default     = ""
}

variable "secret_recovery_window_days" {
  description = "Waiting period before the openai-api-key secret is actually deleted after terraform destroy. 0 = delete immediately, no recovery. 7-30 = AWS recovery window."
  type        = number
  default     = 30

  validation {
    condition     = var.secret_recovery_window_days == 0 || (var.secret_recovery_window_days >= 7 && var.secret_recovery_window_days <= 30)
    error_message = "secret_recovery_window_days must be 0 (immediate delete) or between 7 and 30 (AWS Secrets Manager limits)."
  }
}

variable "tags" {
  description = "Additional tags merged into every resource (Project/Environment/ManagedBy come from provider default_tags)."
  type        = map(string)
  default     = {}
}
