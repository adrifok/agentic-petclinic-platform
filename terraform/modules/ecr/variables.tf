# Module: ecr — input variables
# See docs/technical-spec.md#ecr-container-registry and #terraform-modules.

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

variable "service_names" {
  description = "Microservice names to create one private ECR repository each for, under the petclinic-{environment}/ namespace."
  type        = list(string)

  validation {
    condition     = length(var.service_names) > 0
    error_message = "service_names must contain at least one service name."
  }
}

variable "image_tag_mutability" {
  description = "Tag mutability for all repositories: MUTABLE for dev (allows re-pushing a tag during development), IMMUTABLE for prod (deployed tags can't be overwritten)."
  type        = string
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be \"MUTABLE\" or \"IMMUTABLE\"."
  }
}

variable "max_image_count" {
  description = "Lifecycle policy: expire images beyond this count, across all tags (the effective \"keep last N\" rule)."
  type        = number
  default     = 10
}

variable "untagged_image_expiry_days" {
  description = "Lifecycle policy: expire untagged images older than this many days."
  type        = number
  default     = 7
}

variable "force_delete" {
  description = "Allow terraform destroy to remove a repository even if it still contains images. Defaults to false (safe): a repository with pushed images blocks destroy until images are removed or this is set true. Dev opts in explicitly (see terraform/environments/dev — this is a learning environment torn down/rebuilt to control cost via scripts/stop-env.sh, scripts/start-env.sh); prod should NOT set this true without a deliberate reason."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags merged into every resource (Project/Environment/ManagedBy come from provider default_tags)."
  type        = map(string)
  default     = {}
}
