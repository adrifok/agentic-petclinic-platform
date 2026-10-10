# Root module — prod environment
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

# Implements PETPLAT-17 (wire EKS into prod). Sizing per
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

# Implements PETPLAT-27 (wire RDS into prod). Same instance sizing as dev
# (cost optimization for a learning project — see docs/technical-spec.md#rds-database);
# prod differs on skip_final_snapshot and backup_retention_period only.
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
  secret_recovery_window_days = var.secret_recovery_window_days
  skip_final_snapshot         = var.rds_skip_final_snapshot
  deletion_protection         = var.rds_deletion_protection
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

# Implements PETPLAT-73 (Karpenter AWS prerequisites). Controller IRSA role,
# node instance profile, SQS interruption queue and EventBridge rules — the
# Helm release and NodePool/EC2NodeClass CRDs are installed separately. See
# docs/technical-spec.md#karpenter-node-autoscaling.
module "karpenter" {
  source = "../../modules/karpenter"

  project     = var.project
  environment = var.environment

  cluster_name      = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  node_role_arn     = module.eks.node_role_arn
}

# Implements PETPLAT-75 (budget alerts). No cost filter: dev and prod share
# one AWS account, so this budget tracks the whole account total and the dev
# and prod budgets alert on the same spend. See
# docs/technical-spec.md#scaling-and-cost.
resource "aws_budgets_budget" "monthly" {
  name         = "${var.project}-${var.environment}-monthly-budget"
  budget_type  = "COST"
  limit_amount = var.budget_limit_amount
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  dynamic "notification" {
    for_each = var.budget_alert_thresholds

    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = [var.budget_alert_email]
    }
  }
}
