# Root module variables — prod environment
# See docs/technical-spec.md#general-project-parameters.

variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "eu-central-1"
}

variable "environment" {
  description = "Deployment environment (dev or prod)."
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be \"dev\" or \"prod\"."
  }
}

variable "project" {
  description = "Project name, used in resource naming and tagging."
  type        = string
  default     = "petclinic"
}
