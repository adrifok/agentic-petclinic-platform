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

# --- VPC (see docs/technical-spec.md#vpc-network-design) ---

variable "vpc_cidr" {
  description = "CIDR block for the prod VPC (non-overlapping with dev)."
  type        = string
  default     = "10.1.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs for the prod VPC, one per AZ."
  type        = list(string)
  default     = ["10.1.1.0/24", "10.1.2.0/24"]
}

variable "availability_zones" {
  description = "Availability zones for the prod public subnets."
  type        = list(string)
  default     = ["eu-central-1a", "eu-central-1b"]
}

# --- EKS (see docs/technical-spec.md#eks-cluster) ---

variable "eks_cluster_version" {
  description = "Kubernetes version for the prod EKS cluster. 1.29 (the spec value) is past EKS end of support; 1.36 is the current standard-support default."
  type        = string
  default     = "1.36"
}

variable "eks_node_instance_types" {
  description = "Instance types for the prod EKS managed node group (ARM/Graviton free trial)."
  type        = list(string)
  default     = ["t4g.small"]
}

variable "eks_node_min_size" {
  description = "Minimum node count for the prod EKS node group."
  type        = number
  default     = 2
}

variable "eks_node_max_size" {
  description = "Maximum node count for the prod EKS node group."
  type        = number
  default     = 4
}

variable "eks_node_desired_size" {
  description = "Desired node count for the prod EKS node group."
  type        = number
  default     = 2
}

variable "eks_node_disk_size" {
  description = "Disk size in GB for the prod EKS worker nodes."
  type        = number
  default     = 20
}

variable "eks_node_capacity_type" {
  description = "Capacity type for the prod EKS node group (ON_DEMAND or SPOT)."
  type        = string
  default     = "ON_DEMAND"
}

variable "eks_cluster_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the prod EKS public API endpoint. Restrict to known IPs (office/VPN) before going live — defaults open per ADR-0001's all-public design, but prod should not stay on the wide-open default."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "eks_cluster_log_retention_days" {
  description = "Retention for the prod EKS control plane CloudWatch log group."
  type        = number
  default     = 30
}

# --- RDS (see docs/technical-spec.md#rds-database) ---

variable "rds_instance_class" {
  description = "RDS instance class for prod (free tier, ARM/Graviton — same as dev, cost optimization for a learning project; use a larger class with Multi-AZ in a real production environment)."
  type        = string
  default     = "db.t4g.micro"
}

variable "rds_allocated_storage" {
  description = "Initial RDS storage in GB for prod."
  type        = number
  default     = 20
}

variable "rds_max_allocated_storage" {
  description = "Max autoscale RDS storage in GB for prod."
  type        = number
  default     = 20
}

variable "rds_multi_az" {
  description = "Multi-AZ for prod RDS (false — single-AZ to save cost for a learning project; enable Multi-AZ in real production)."
  type        = bool
  default     = false
}

variable "rds_backup_retention_period" {
  description = "Automated backup retention in days for prod RDS."
  type        = number
  default     = 30
}

variable "rds_skip_final_snapshot" {
  description = "Skip final snapshot on destroy for prod RDS (false — prod keeps a final snapshot on teardown)."
  type        = bool
  default     = false
}

variable "rds_deletion_protection" {
  description = "Deletion protection for prod RDS. Deviates from docs/technical-spec.md's Deletion Protection row (which pins both envs to false) — unlike Multi-AZ/backup retention this control is free, so it's enabled for prod as a guard against an accidental terraform destroy/replace or console deletion. Dev stays false (torn down/rebuilt intentionally)."
  type        = bool
  default     = true
}
