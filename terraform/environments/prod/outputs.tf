# Root module outputs — prod environment
#
# Populated as each module is wired in (cluster_endpoint, rds endpoint, ECR
# repository URLs, etc.).

output "vpc_id" {
  description = "Prod VPC ID."
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Prod public subnet IDs."
  value       = module.vpc.public_subnet_ids
}

output "igw_id" {
  description = "Prod Internet Gateway ID."
  value       = module.vpc.igw_id
}

output "eks_cluster_sg_id" {
  description = "Prod EKS control plane security group ID."
  value       = module.vpc.eks_cluster_sg_id
}

output "eks_node_sg_id" {
  description = "Prod EKS worker node security group ID."
  value       = module.vpc.eks_node_sg_id
}

output "rds_sg_id" {
  description = "Prod RDS security group ID."
  value       = module.vpc.rds_sg_id
}

output "alb_sg_id" {
  description = "Prod ALB security group ID."
  value       = module.vpc.alb_sg_id
}

output "vpc_flow_log_group_name" {
  description = "Prod CloudWatch log group name for VPC flow logs."
  value       = module.vpc.flow_log_group_name
}

output "cluster_name" {
  description = "Prod EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Prod EKS API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_ca_certificate" {
  description = "Prod EKS cluster CA certificate (base64)."
  value       = module.eks.cluster_ca_certificate
}

output "oidc_provider_arn" {
  description = "Prod EKS OIDC provider ARN (for IRSA trust policies)."
  value       = module.eks.oidc_provider_arn
}

output "oidc_provider_url" {
  description = "Prod EKS OIDC provider issuer URL (for IRSA trust policies)."
  value       = module.eks.oidc_provider_url
}

output "node_group_name" {
  description = "Prod EKS managed node group name."
  value       = module.eks.node_group_name
}

output "node_role_arn" {
  description = "Prod EKS node IAM role ARN."
  value       = module.eks.node_role_arn
}

output "ebs_csi_role_arn" {
  description = "Prod IRSA role ARN for the EBS CSI Driver add-on."
  value       = module.eks.ebs_csi_role_arn
}

output "eso_role_arn" {
  description = "Prod IRSA role ARN for the External Secrets Operator ServiceAccount — pass to scripts/install-external-secrets.sh (PETPLAT-37)."
  value       = module.eks.eso_role_arn
}

output "kubeconfig_command" {
  description = "Command to update local kubeconfig for the prod cluster."
  value       = module.eks.kubeconfig_command
}

output "secrets_kms_key_arn" {
  description = "Prod KMS key ARN used for EKS secrets envelope encryption."
  value       = module.eks.secrets_kms_key_arn
}

output "eks_addon_versions" {
  description = "Prod installed EKS add-on versions (coredns, kube-proxy, vpc-cni, aws-ebs-csi-driver)."
  value = {
    coredns            = module.eks.coredns_addon_version
    kube_proxy         = module.eks.kube_proxy_addon_version
    vpc_cni            = module.eks.vpc_cni_addon_version
    aws_ebs_csi_driver = module.eks.ebs_csi_addon_version
  }
}

output "rds_endpoint" {
  description = "Prod RDS endpoint hostname."
  value       = module.rds.endpoint
}

output "rds_port" {
  description = "Prod RDS port."
  value       = module.rds.port
}

output "rds_db_instance_id" {
  description = "Prod RDS instance ID."
  value       = module.rds.db_instance_id
}

output "rds_db_name" {
  description = "Prod RDS shared database name."
  value       = module.rds.db_name
}

output "rds_secret_arn" {
  description = "Prod Secrets Manager ARN for RDS credentials."
  value       = module.rds.secret_arn
}

output "rds_secret_name" {
  description = "Prod Secrets Manager secret name for RDS credentials."
  value       = module.rds.secret_name
}

output "openai_secret_arn" {
  description = "Prod Secrets Manager ARN for the OpenAI API key."
  value       = module.secrets.openai_secret_arn
}

output "openai_secret_name" {
  description = "Prod Secrets Manager secret name for the OpenAI API key."
  value       = module.secrets.openai_secret_name
}
