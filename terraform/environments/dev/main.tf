# Root module — dev environment
#
# Module wiring (EKS, ECR, RDS, DNS, Secrets) lands with the epics that own
# each module (E-3 through E-7). Provider (providers.tf) and version
# constraints (versions.tf) are configured — see PETPLAT-5.

module "vpc" {
  source = "../../modules/vpc"

  project                  = var.project
  environment              = var.environment
  vpc_cidr                 = var.vpc_cidr
  public_subnet_cidrs      = var.public_subnet_cidrs
  availability_zones       = var.availability_zones
  kms_deletion_window_days = var.kms_deletion_window_days
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
  kms_deletion_window_days             = var.kms_deletion_window_days
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

# Implements PETPLAT-20 (wire ECR into dev). One repo per service, MUTABLE
# tags (dev only — see docs/technical-spec.md#ecr-container-registry).
module "ecr" {
  source = "../../modules/ecr"

  project     = var.project
  environment = var.environment

  service_names        = var.ecr_service_names
  image_tag_mutability = var.ecr_image_tag_mutability
  force_delete         = var.ecr_force_delete
}

# Implements PETPLAT-25 (wire RDS into dev). Single shared `petclinic`
# database for customers/visits/vets services — see
# docs/technical-spec.md#rds-database and docs/runbooks/rds-database-init.md.
module "rds" {
  source = "../../modules/rds"

  project     = var.project
  environment = var.environment

  subnet_ids        = module.vpc.public_subnet_ids
  security_group_id = module.vpc.rds_sg_id

  instance_class              = var.rds_instance_class
  allocated_storage           = var.rds_allocated_storage
  max_allocated_storage       = var.rds_max_allocated_storage
  multi_az                    = var.rds_multi_az
  backup_retention_period     = var.rds_backup_retention_period
  skip_final_snapshot         = var.rds_skip_final_snapshot
  deletion_protection         = var.rds_deletion_protection
  secret_recovery_window_days = var.secret_recovery_window_days
}

# Implements PETPLAT-32 (wire DNS into dev). Hosted zone + wildcard ACM
# certificate now; the ALB alias record (PETPLAT-31) turns on once the LB
# controller + Ingress are deployed and dns_create_alb_record is set to true
# in terraform.tfvars — see docs/technical-spec.md#dns-and-ingress.
module "dns" {
  source = "../../modules/dns"

  project     = var.project
  environment = var.environment
  domain_name = var.domain_name

  # Registered via Route 53 Domain Registration, which already auto-created
  # a hosted zone and delegated the domain's NS records to it — this module
  # looks that zone up instead of creating a duplicate one (see
  # terraform/modules/dns/main.tf).
  create_hosted_zone = var.dns_create_hosted_zone

  create_alb_record = var.dns_create_alb_record
  alb_dns_name      = var.dns_alb_dns_name
  alb_zone_id       = var.dns_alb_zone_id
}

# Implements PETPLAT-33 (non-RDS secrets). RDS credentials are created by the
# rds module (PETPLAT-23) — this module handles the OpenAI API key only. See
# docs/technical-spec.md#secrets-management.
module "secrets" {
  source = "../../modules/secrets"

  project     = var.project
  environment = var.environment

  openai_api_key              = var.openai_api_key
  secret_recovery_window_days = var.secret_recovery_window_days
}
