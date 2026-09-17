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
  description = "OpenAI API key for genai-service, stored in Secrets Manager as petclinic/{env}/openai-api-key. Never hardcode — pass via terraform.tfvars (gitignored) or TF_VAR_openai_api_key."
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Additional tags merged into every resource (Project/Environment/ManagedBy come from provider default_tags)."
  type        = map(string)
  default     = {}
}
