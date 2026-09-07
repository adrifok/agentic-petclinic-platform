# Root module — dev environment
#
# Module wiring (EKS, ECR, RDS, DNS, Secrets) lands with the epics that own
# each module (E-3 through E-7). Provider (providers.tf) and version
# constraints (versions.tf) are configured — see PETPLAT-5.

module "vpc" {
  source = "../../modules/vpc"

  project             = var.project
  environment         = var.environment
  vpc_cidr            = var.vpc_cidr
  public_subnet_cidrs = var.public_subnet_cidrs
  availability_zones  = var.availability_zones
}

# Implements PETPLAT-15 (wire EKS into dev). Sizing per
# docs/technical-spec.md#eks-cluster — dev and prod are intentionally
# identical (cost optimization for a learning project).
module "eks" {
  source = "../../modules/eks"

  project     = var.project
  environment = var.environment

  cluster_version                      = var.eks_cluster_version
  cluster_endpoint_public_access_cidrs = var.eks_cluster_endpoint_public_access_cidrs
  cluster_log_retention_days           = var.eks_cluster_log_retention_days
  subnet_ids                           = module.vpc.public_subnet_ids
  cluster_sg_id                        = module.vpc.eks_cluster_sg_id
  node_sg_id                           = module.vpc.eks_node_sg_id

  node_instance_types = var.eks_node_instance_types
  node_capacity_type  = var.eks_node_capacity_type
  node_disk_size      = var.eks_node_disk_size
  node_min_size       = var.eks_node_min_size
  node_max_size       = var.eks_node_max_size
  node_desired_size   = var.eks_node_desired_size
}
