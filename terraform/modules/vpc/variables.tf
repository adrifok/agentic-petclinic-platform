# Module: vpc — input variables
# See docs/technical-spec.md#vpc-network-design and #security-groups.

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

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnets, one per availability zone (order matches availability_zones)."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) == 2
    error_message = "public_subnet_cidrs must contain exactly 2 CIDRs (2 AZs — see docs/technical-spec.md#vpc-network-design)."
  }
}

variable "availability_zones" {
  description = "Availability zones for the public subnets, one per subnet (order matches public_subnet_cidrs)."
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) == 2
    error_message = "availability_zones must contain exactly 2 AZs."
  }
}

variable "tags" {
  description = "Additional tags merged into every resource (Project/Environment/ManagedBy come from provider default_tags)."
  type        = map(string)
  default     = {}
}

variable "flow_log_traffic_type" {
  description = "Traffic captured by the VPC flow log (ACCEPT, REJECT, or ALL)."
  type        = string
  default     = "ALL"

  validation {
    condition     = contains(["ACCEPT", "REJECT", "ALL"], var.flow_log_traffic_type)
    error_message = "flow_log_traffic_type must be \"ACCEPT\", \"REJECT\", or \"ALL\"."
  }
}

variable "flow_log_retention_days" {
  description = "Retention for the VPC flow log CloudWatch log group."
  type        = number
  default     = 30
}
