# Root module outputs — dev environment
#
# Populated as each module is wired in (cluster_endpoint, rds endpoint, ECR
# repository URLs, etc.).

output "vpc_id" {
  description = "Dev VPC ID."
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Dev public subnet IDs."
  value       = module.vpc.public_subnet_ids
}

output "igw_id" {
  description = "Dev Internet Gateway ID."
  value       = module.vpc.igw_id
}

output "eks_cluster_sg_id" {
  description = "Dev EKS control plane security group ID."
  value       = module.vpc.eks_cluster_sg_id
}

output "eks_node_sg_id" {
  description = "Dev EKS worker node security group ID."
  value       = module.vpc.eks_node_sg_id
}

output "rds_sg_id" {
  description = "Dev RDS security group ID."
  value       = module.vpc.rds_sg_id
}

output "alb_sg_id" {
  description = "Dev ALB security group ID."
  value       = module.vpc.alb_sg_id
}

output "vpc_flow_log_group_name" {
  description = "Dev CloudWatch log group name for VPC flow logs."
  value       = module.vpc.flow_log_group_name
}

output "cluster_name" {
  description = "Dev EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Dev EKS API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_ca_certificate" {
  description = "Dev EKS cluster CA certificate (base64)."
  value       = module.eks.cluster_ca_certificate
}

output "oidc_provider_arn" {
  description = "Dev EKS OIDC provider ARN (for IRSA trust policies)."
  value       = module.eks.oidc_provider_arn
}

output "oidc_provider_url" {
  description = "Dev EKS OIDC provider issuer URL (for IRSA trust policies)."
  value       = module.eks.oidc_provider_url
}

output "node_group_name" {
  description = "Dev EKS managed node group name."
  value       = module.eks.node_group_name
}

output "node_role_arn" {
  description = "Dev EKS node IAM role ARN."
  value       = module.eks.node_role_arn
}

output "ebs_csi_role_arn" {
  description = "Dev IRSA role ARN for the EBS CSI Driver add-on."
  value       = module.eks.ebs_csi_role_arn
}

output "lb_controller_role_arn" {
  description = "Dev IRSA role ARN for the AWS Load Balancer Controller ServiceAccount — pass to scripts/install-lb-controller.sh (PETPLAT-29)."
  value       = module.eks.lb_controller_role_arn
}

output "kubeconfig_command" {
  description = "Command to update local kubeconfig for the dev cluster."
  value       = module.eks.kubeconfig_command
}

output "secrets_kms_key_arn" {
  description = "Dev KMS key ARN used for EKS secrets envelope encryption."
  value       = module.eks.secrets_kms_key_arn
}

output "eks_addon_versions" {
  description = "Dev installed EKS add-on versions (coredns, kube-proxy, vpc-cni, aws-ebs-csi-driver)."
  value = {
    coredns            = module.eks.coredns_addon_version
    kube_proxy         = module.eks.kube_proxy_addon_version
    vpc_cni            = module.eks.vpc_cni_addon_version
    aws_ebs_csi_driver = module.eks.ebs_csi_addon_version
  }
}

output "ecr_repository_urls" {
  description = "Dev ECR repository URLs, keyed by service name."
  value       = module.ecr.repository_urls
}

output "ecr_repository_arns" {
  description = "Dev ECR repository ARNs, keyed by service name."
  value       = module.ecr.repository_arns
}

output "rds_endpoint" {
  description = "Dev RDS endpoint hostname."
  value       = module.rds.endpoint
}

output "rds_port" {
  description = "Dev RDS port."
  value       = module.rds.port
}

output "rds_db_instance_id" {
  description = "Dev RDS instance ID."
  value       = module.rds.db_instance_id
}

output "rds_db_name" {
  description = "Dev RDS shared database name."
  value       = module.rds.db_name
}

output "rds_secret_arn" {
  description = "Dev Secrets Manager ARN for RDS credentials."
  value       = module.rds.secret_arn
}

output "rds_secret_name" {
  description = "Dev Secrets Manager secret name for RDS credentials."
  value       = module.rds.secret_name
}

output "dns_zone_id" {
  description = "Dev Route 53 hosted zone ID."
  value       = module.dns.zone_id
}

output "dns_name_servers" {
  description = "Dev Route 53 hosted zone name servers — delegate var.domain_name to these at the registrar."
  value       = module.dns.name_servers
}

output "dns_certificate_arn" {
  description = "Dev validated ACM certificate ARN — pass to the Ingress's alb.ingress.kubernetes.io/certificate-arn annotation (PETPLAT-30)."
  value       = module.dns.certificate_arn
}

output "dns_record_name" {
  description = "Dev FQDN (petclinic-dev.{domain_name}) the ALB alias record will use once PETPLAT-31 is enabled."
  value       = module.dns.record_name
}

output "dns_alb_record_fqdn" {
  description = "FQDN of the created ALB alias record, or null until dns_create_alb_record is set to true (PETPLAT-31)."
  value       = module.dns.alb_record_fqdn
}
