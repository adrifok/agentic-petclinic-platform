# Root module variables — dev environment
# See docs/technical-spec.md#general-project-parameters.

variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "eu-central-1"
}

variable "environment" {
  description = "Deployment environment (dev or prod)."
  type        = string
  default     = "dev"

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

# --- VPC (see docs/technical-spec.md#vpc-network-design) ---

variable "vpc_cidr" {
  description = "CIDR block for the dev VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs for the dev VPC, one per AZ."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "availability_zones" {
  description = "Availability zones for the dev public subnets."
  type        = list(string)
  default     = ["eu-central-1a", "eu-central-1b"]
}

# --- EKS (see docs/technical-spec.md#eks-cluster) ---

variable "eks_cluster_version" {
  description = "Kubernetes version for the dev EKS cluster. 1.29 (the spec value) is past EKS end of support; 1.36 is the current standard-support default."
  type        = string
  default     = "1.36"
}

variable "eks_node_instance_types" {
  description = "Instance types for the dev EKS managed node group (ARM/Graviton free trial)."
  type        = list(string)
  default     = ["t4g.small"]
}

variable "eks_node_min_size" {
  description = "Minimum node count for the dev EKS node group."
  type        = number
  default     = 2
}

variable "eks_node_max_size" {
  description = "Maximum node count for the dev EKS node group."
  type        = number
  default     = 4
}

variable "eks_node_desired_size" {
  description = "Desired node count for the dev EKS node group."
  type        = number
  default     = 2
}

variable "eks_node_disk_size" {
  description = "Disk size in GB for the dev EKS worker nodes."
  type        = number
  default     = 20
}

variable "eks_node_capacity_type" {
  description = "Capacity type for the dev EKS node group (ON_DEMAND or SPOT)."
  type        = string
  default     = "ON_DEMAND"
}

variable "eks_cluster_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the dev EKS public API endpoint. Restrict to known IPs (office/VPN) where possible — defaults open per ADR-0001's all-public design."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "eks_cluster_log_retention_days" {
  description = "Retention for the dev EKS control plane CloudWatch log group."
  type        = number
  default     = 30
}

# --- ECR (see docs/technical-spec.md#ecr-container-registry) ---

variable "ecr_service_names" {
  description = "Microservice names for ECR repositories, one repo each under petclinic-dev/."
  type        = list(string)
  default = [
    "config-server",
    "discovery-server",
    "api-gateway",
    "customers-service",
    "visits-service",
    "vets-service",
    "genai-service",
    "admin-server",
  ]
}

variable "ecr_image_tag_mutability" {
  description = "ECR tag mutability for dev (MUTABLE — allows re-pushing a tag during development)."
  type        = string
  default     = "MUTABLE"
}

variable "ecr_force_delete" {
  description = "Allow terraform destroy to remove dev ECR repositories even if they still contain images. True in dev only — this environment is torn down/rebuilt regularly to control cost (see scripts/stop-env.sh, scripts/start-env.sh); the module itself defaults to false."
  type        = bool
  default     = true
}
