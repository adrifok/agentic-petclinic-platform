# Module: github-oidc — input variables
# See docs/technical-spec.md#oidc-federation-no-long-lived-credentials.

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

variable "create_oidc_provider" {
  description = "Create the GitHub Actions IAM OIDC provider. It is account-global (one per URL), so only one environment may own it — the other sets this false and passes existing_oidc_provider_arn."
  type        = bool
  default     = true
}

variable "existing_oidc_provider_arn" {
  description = "ARN of an already-existing token.actions.githubusercontent.com OIDC provider. Required when create_oidc_provider is false."
  type        = string
  default     = ""
}

variable "oidc_thumbprints" {
  description = "Thumbprints for token.actions.githubusercontent.com. AWS no longer validates these for GitHub's IdP (it uses its own trusted CA list), but the API still accepts/stores them."
  type        = list(string)
  default = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

variable "github_owner" {
  description = "GitHub user/org that owns the application repo fork the build workflow runs in."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9-]+$", var.github_owner))
    error_message = "github_owner must be a literal GitHub user/org name (no wildcards)."
  }
}

variable "github_repo" {
  description = "Application repo name (the build workflow's repo context — not the platform repo)."
  type        = string
  default     = "spring-petclinic-microservices"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+$", var.github_repo))
    error_message = "github_repo must be a literal repo name (no wildcards)."
  }
}

variable "github_owner_id" {
  description = "Numeric GitHub account ID of github_owner. Set together with github_repo_id when the repo uses immutable OIDC subject claims (gh api repos/{owner}/{repo}/actions/oidc/customization/sub shows use_immutable_subject). Empty = legacy sub format."
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[0-9]*$", var.github_owner_id))
    error_message = "github_owner_id must be numeric (or empty)."
  }
}

variable "github_repo_id" {
  description = "Numeric GitHub repository ID. Set together with github_owner_id for immutable OIDC subject claims. Empty = legacy sub format."
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[0-9]*$", var.github_repo_id))
    error_message = "github_repo_id must be numeric (or empty)."
  }
}

variable "github_branch" {
  description = "Only workflow runs on this branch can assume the role."
  type        = string
  default     = "main"

  validation {
    condition     = can(regex("^[A-Za-z0-9._/-]+$", var.github_branch))
    error_message = "github_branch must be a literal branch name (no wildcards)."
  }
}

variable "ecr_repository_arns" {
  description = "ECR repository ARNs the role may push to (from the ecr module's repository_arns output)."
  type        = list(string)

  validation {
    condition     = length(var.ecr_repository_arns) > 0
    error_message = "ecr_repository_arns must contain at least one repository ARN."
  }
}

variable "max_session_duration" {
  description = "Maximum role session duration in seconds."
  type        = number
  default     = 3600
}

variable "tags" {
  description = "Additional tags merged into every resource (Project/Environment/ManagedBy come from provider default_tags)."
  type        = map(string)
  default     = {}
}
