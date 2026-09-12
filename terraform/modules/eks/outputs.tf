# Module: eks — outputs
# See docs/technical-spec.md#terraform-modules.

output "cluster_name" {
  description = "EKS cluster name."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  description = "Cluster CA certificate (base64)."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN (for IRSA trust policies)."
  value       = aws_iam_openid_connect_provider.this.arn
}

output "oidc_provider_url" {
  description = "OIDC provider issuer URL (for IRSA trust policies)."
  value       = aws_iam_openid_connect_provider.this.url
}

output "node_group_name" {
  description = "Managed node group name."
  value       = aws_eks_node_group.this.node_group_name
}

output "node_role_arn" {
  description = "Node IAM role ARN."
  value       = aws_iam_role.node.arn
}

output "ebs_csi_role_arn" {
  description = "IRSA role ARN for the EBS CSI Driver add-on."
  value       = aws_iam_role.ebs_csi.arn
}

output "lb_controller_role_arn" {
  description = "IRSA role ARN for the AWS Load Balancer Controller ServiceAccount (kube-system/aws-load-balancer-controller) — PETPLAT-29."
  value       = aws_iam_role.lb_controller.arn
}

output "kubeconfig_command" {
  description = "Command to update local kubeconfig for this cluster (PETPLAT-14)."
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.this.name} --region ${data.aws_region.current.name}"
}

output "secrets_kms_key_arn" {
  description = "KMS key ARN used for EKS secrets envelope encryption."
  value       = aws_kms_key.eks_secrets.arn
}

output "cluster_log_group_name" {
  description = "CloudWatch log group name for the EKS control plane logs."
  value       = aws_cloudwatch_log_group.cluster.name
}

# Actual installed add-on versions (PETPLAT-84) — useful for confirming what
# a "null → resolve most recent" default actually resolved to.
output "coredns_addon_version" {
  description = "Installed coredns add-on version."
  value       = aws_eks_addon.coredns.addon_version
}

output "kube_proxy_addon_version" {
  description = "Installed kube-proxy add-on version."
  value       = aws_eks_addon.kube_proxy.addon_version
}

output "vpc_cni_addon_version" {
  description = "Installed vpc-cni add-on version."
  value       = aws_eks_addon.vpc_cni.addon_version
}

output "ebs_csi_addon_version" {
  description = "Installed aws-ebs-csi-driver add-on version."
  value       = aws_eks_addon.ebs_csi.addon_version
}
