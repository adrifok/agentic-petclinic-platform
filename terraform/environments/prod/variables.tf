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
  description = "CIDRs allowed to reach the prod EKS public API endpoint (operator IPs, e.g. [\"203.0.113.10/32\"]). Required, no default; prefixes wider than /24 are rejected (PET-6). Nodes and pods use the private endpoint, so this only gates operator kubectl/helm scripts from outside the VPC (prod Terraform has no kubernetes/helm provider)."
  type        = list(string)

  validation {
    condition     = length(var.eks_cluster_endpoint_public_access_cidrs) > 0 && alltrue([for c in var.eks_cluster_endpoint_public_access_cidrs : can(cidrhost(c, 0)) && try(tonumber(split("/", c)[1]) >= 24, false)])
    error_message = "eks_cluster_endpoint_public_access_cidrs must be a non-empty list of valid CIDRs, each /24 or narrower (0.0.0.0/0 and other wide ranges are rejected)."
  }
}

variable "eks_cluster_log_retention_days" {
  description = "Retention for the prod EKS control plane CloudWatch log group."
  type        = number
  default     = 30
}

variable "kms_deletion_window_days" {
  description = "Waiting period before prod's KMS keys (eks_secrets, flow_log) are actually deleted after terraform destroy. 30 (the AWS max) — prod isn't churned like dev, so the longer window is kept as a recovery buffer against an accidental/malicious key deletion."
  type        = number
  default     = 30
}

variable "secret_recovery_window_days" {
  description = "Waiting period before prod's Secrets Manager secrets (rds-credentials, openai-api-key) are actually deleted after terraform destroy. 30 (the AWS max) — prod isn't churned like dev, so the longer window is kept as a recovery buffer against an accidental/malicious secret deletion."
  type        = number
  default     = 30

  validation {
    condition     = var.secret_recovery_window_days == 0 || (var.secret_recovery_window_days >= 7 && var.secret_recovery_window_days <= 30)
    error_message = "secret_recovery_window_days must be 0 (immediate delete) or between 7 and 30 (AWS Secrets Manager limits)."
  }
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

# --- Secrets (see docs/technical-spec.md#secrets-management) ---

variable "openai_api_key" {
  description = "OpenAI API key for genai-service, stored in Secrets Manager as petclinic/prod/openai-api-key. Set the real value in terraform.tfvars (gitignored) or TF_VAR_openai_api_key — never commit it. genai-service is optional — leave unset (empty) to skip it."
  type        = string
  sensitive   = true
  default     = ""
}

# --- Budget alerts (see docs/technical-spec.md#scaling-and-cost) ---

variable "budget_limit_amount" {
  description = "Monthly cost budget for prod in USD."
  type        = string
  default     = "100"
}

variable "budget_alert_thresholds" {
  description = "Percentages of the monthly budget (actual spend) that trigger an email alert."
  type        = list(number)
  default     = [50, 80, 100]
}

variable "budget_alert_email" {
  description = "Email address that receives prod budget alerts. Set in terraform.tfvars (gitignored)."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.budget_alert_email))
    error_message = "budget_alert_email must be a valid email address."
  }
}

variable "ecr_service_names" {
  description = "Microservice names for prod ECR repositories, one repo each under petclinic-prod/ (same list as dev, so promotion has a source repo for each)."
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

variable "github_owner" {
  description = "GitHub user owning the platform repo."
  type        = string
  default     = "adrifok"
}

variable "github_owner_id" {
  description = "Numeric GitHub account ID of github_owner, for immutable OIDC subject claims. gh api users/adrifok -q .id"
  type        = string
  default     = "97637423"
}

variable "github_platform_repo" {
  description = "Platform repo whose promote-images workflow may assume the prod CI role (PET-7)."
  type        = string
  default     = "agentic-petclinic-platform"
}

variable "github_platform_repo_id" {
  description = "Numeric repository ID of the platform repo, for immutable OIDC subject claims. gh api repos/adrifok/agentic-petclinic-platform -q .id"
  type        = string
  default     = "1355981888"
}

variable "domain_name" {
  description = "Apex domain, same Route 53 zone as dev (PET-12). Prod record: petclinic.{domain_name}. Set in terraform.tfvars."
  type        = string
}

variable "dns_create_alb_record" {
  description = "Create the petclinic.{domain_name} alias to the prod ALB. False until the prod Ingress has created the ALB (PET-14)."
  type        = bool
  default     = false
}

variable "dns_alb_dns_name" {
  description = "DNS name of the prod ALB (kubectl get ingress api-gateway -n petclinic-prod). Required when dns_create_alb_record is true."
  type        = string
  default     = ""
}

variable "dns_alb_zone_id" {
  description = "Canonical hosted zone ID of the prod ALB (aws elbv2 describe-load-balancers). Required when dns_create_alb_record is true."
  type        = string
  default     = ""
}
