# Module: karpenter — input variables
# See docs/technical-spec.md#module-karpenter.

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

variable "cluster_name" {
  description = "EKS cluster name (from the eks module output)."
  type        = string
}

variable "oidc_provider_arn" {
  description = "EKS OIDC provider ARN, used as the federated principal in the Karpenter IRSA trust policy (from the eks module output)."
  type        = string
}

variable "oidc_provider_url" {
  description = "EKS OIDC provider issuer URL, used in the IRSA trust policy sub/aud conditions (from the eks module output). The https:// scheme is stripped inside the module."
  type        = string
}

variable "node_role_arn" {
  description = "Node IAM role ARN (from the eks module output). Wrapped in the Karpenter node instance profile and the only role Karpenter may pass to EC2."
  type        = string
}

variable "tags" {
  description = "Additional tags merged onto every resource (Project/Environment/ManagedBy come from provider default_tags)."
  type        = map(string)
  default     = {}
}
