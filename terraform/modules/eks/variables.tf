# Module: eks — input variables
# See docs/technical-spec.md#eks-cluster and #terraform-modules.

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

# --- Cluster ---

variable "cluster_version" {
  description = "Kubernetes version for the EKS control plane. docs/technical-spec.md specifies \"1.29+\"; 1.29 itself is no longer offered by EKS for new clusters (past end of support), so this defaults to 1.36 — the current AWS default/standard-support version, avoiding the extra per-hour charge EKS applies to clusters in extended support (1.31-1.33)."
  type        = string
  default     = "1.36"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.cluster_version))
    error_message = "cluster_version must be a Kubernetes minor version like \"1.36\"."
  }
}

variable "cluster_log_retention_days" {
  description = "Retention for the EKS control plane CloudWatch log group."
  type        = number
  default     = 30
}

variable "subnet_ids" {
  description = "Subnet IDs for the cluster and node group (public subnets — see ADR-0001)."
  type        = list(string)
}

variable "cluster_sg_id" {
  description = "EKS control plane security group ID (from the vpc module)."
  type        = string
}

variable "node_sg_id" {
  description = "EKS worker node security group ID (from the vpc module), attached via the node group launch template."
  type        = string
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public API server endpoint. Restrict to known IPs where possible; defaults to open for a learning environment."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# --- Managed node group ---

variable "node_instance_types" {
  description = "Instance types for the managed node group."
  type        = list(string)
  default     = ["t4g.small"]
}

variable "node_ami_type" {
  description = "AMI type for worker nodes. AL2 has no ARM64 build for current EKS versions (AWS deprecated AL2 EKS-optimized AMIs) — AL2023_ARM_64_STANDARD is the replacement."
  type        = string
  default     = "AL2023_ARM_64_STANDARD"
}

variable "node_capacity_type" {
  description = "Capacity type for the node group (ON_DEMAND or SPOT)."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type must be \"ON_DEMAND\" or \"SPOT\"."
  }
}

variable "node_min_size" {
  description = "Minimum node count."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum node count."
  type        = number
  default     = 4
}

variable "node_desired_size" {
  description = "Desired node count."
  type        = number
  default     = 2
}

variable "node_disk_size" {
  description = "Disk size in GB for worker nodes."
  type        = number
  default     = 20
}

variable "node_labels" {
  description = "Additional Kubernetes labels applied to the node group (merged with environment/managed-by)."
  type        = map(string)
  default     = {}
}

variable "node_taints" {
  description = "Kubernetes taints applied to the node group."
  type = list(object({
    key    = string
    value  = optional(string)
    effect = string
  }))
  default = []
}

# --- kubectl / access entries (PETPLAT-14) ---

variable "grant_caller_cluster_admin" {
  description = "Whether to create an EKS access entry granting the identity running Terraform cluster-admin access. See docs/runbooks/eks-access.md to add others."
  type        = bool
  default     = true
}

variable "additional_access_entries" {
  description = "Extra IAM principals to grant EKS access. Each gets an access entry plus the given access policy — scoped to `namespaces` when given, cluster-wide otherwise. Defaults to read-only (AmazonEKSViewPolicy); pass a more privileged policy_arn explicitly. See docs/runbooks/eks-access.md."
  type = list(object({
    principal_arn     = string
    policy_arn        = optional(string, "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy")
    kubernetes_groups = optional(list(string), [])
    namespaces        = optional(list(string), [])
  }))
  default = []
}

# --- Add-ons (PETPLAT-84) ---
#
# Versions are resolved via the aws_eks_addon_version data source (most recent
# build compatible with cluster_version) unless an explicit override is given
# below. This keeps add-ons pinned to a concrete version string (never the
# literal "latest") while avoiding hardcoded versions that drift out of sync
# with the cluster's Kubernetes version. See docs/runbooks/eks-access.md for
# the upgrade procedure.

variable "coredns_addon_version" {
  description = "Explicit coredns add-on version to pin (e.g. v1.11.1-eksbuild.4). Null resolves to the most recent version compatible with cluster_version."
  type        = string
  default     = null
}

variable "kube_proxy_addon_version" {
  description = "Explicit kube-proxy add-on version to pin. Null resolves to the most recent version compatible with cluster_version."
  type        = string
  default     = null
}

variable "vpc_cni_addon_version" {
  description = "Explicit vpc-cni add-on version to pin. Null resolves to the most recent version compatible with cluster_version."
  type        = string
  default     = null
}

variable "ebs_csi_addon_version" {
  description = "Explicit aws-ebs-csi-driver add-on version to pin. Null resolves to the most recent version compatible with cluster_version."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags merged into every resource (Project/Environment/ManagedBy come from provider default_tags)."
  type        = map(string)
  default     = {}
}
