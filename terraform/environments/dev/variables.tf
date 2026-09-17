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

variable "kms_deletion_window_days" {
  description = "Waiting period before dev's KMS keys (eks_secrets, flow_log) are actually deleted after terraform destroy. 7 (the AWS minimum) — dev is torn down/rebuilt regularly to control cost (see scripts/stop-env.sh), so this caps the lingering per-key cost instead of the 30-day default."
  type        = number
  default     = 7
}

variable "rds_secret_recovery_window_days" {
  description = "Waiting period before dev's rds-credentials secret is actually deleted after terraform destroy. 0 — dev is torn down/rebuilt regularly (see scripts/stop-env.sh); a nonzero window leaves the secret in a pending-deletion state that blocks the next apply from recreating it (name collision) until the window elapses or it's manually restored/force-deleted."
  type        = number
  default     = 0

  validation {
    condition     = var.rds_secret_recovery_window_days == 0 || (var.rds_secret_recovery_window_days >= 7 && var.rds_secret_recovery_window_days <= 30)
    error_message = "rds_secret_recovery_window_days must be 0 (immediate delete) or between 7 and 30 (AWS Secrets Manager limits)."
  }
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

# --- RDS (see docs/technical-spec.md#rds-database) ---

variable "rds_instance_class" {
  description = "RDS instance class for dev (free tier, ARM/Graviton)."
  type        = string
  default     = "db.t4g.micro"
}

variable "rds_allocated_storage" {
  description = "Initial RDS storage in GB for dev."
  type        = number
  default     = 20
}

variable "rds_max_allocated_storage" {
  description = "Max autoscale RDS storage in GB for dev."
  type        = number
  default     = 20
}

variable "rds_multi_az" {
  description = "Multi-AZ for dev RDS (false — cost optimization for a learning project)."
  type        = bool
  default     = false
}

variable "rds_backup_retention_period" {
  description = "Automated backup retention in days for dev RDS."
  type        = number
  default     = 7
}

variable "rds_skip_final_snapshot" {
  description = "Skip final snapshot on destroy for dev RDS (true — dev is torn down/rebuilt regularly, see scripts/stop-env.sh)."
  type        = bool
  default     = true
}

variable "rds_deletion_protection" {
  description = "Deletion protection for dev RDS."
  type        = bool
  default     = false
}

# --- DNS (see docs/technical-spec.md#dns-and-ingress) ---

variable "domain_name" {
  description = "Apex domain for dev (e.g. \"example.com\"). Route 53 record will be petclinic-dev.{domain_name}. Set the real, owned domain in terraform.tfvars."
  type        = string
}

variable "dns_create_hosted_zone" {
  description = "Whether the dns module creates a new Route 53 hosted zone for domain_name. False when the domain was registered via Route 53 Domain Registration (auto-creates its own zone already — see terraform/modules/dns/main.tf); true only for a domain bought elsewhere with no existing zone."
  type        = bool
  default     = false
}

variable "dns_create_alb_record" {
  description = "Whether to create the Route 53 alias record for the dev ALB (PETPLAT-31). False until the AWS Load Balancer Controller and Ingress (PETPLAT-29, PETPLAT-30) are deployed and the ALB exists."
  type        = bool
  default     = false
}

variable "dns_alb_dns_name" {
  description = "DNS name of the dev ALB (from `kubectl get ingress api-gateway -n petclinic-dev`). Required when dns_create_alb_record is true."
  type        = string
  default     = ""
}

variable "dns_alb_zone_id" {
  description = "Canonical hosted zone ID of the dev ALB (from `aws elbv2 describe-load-balancers`). Required when dns_create_alb_record is true."
  type        = string
  default     = ""
}
