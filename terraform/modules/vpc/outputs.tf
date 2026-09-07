# Module: vpc — outputs
# See docs/technical-spec.md#terraform-modules.

output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs (2, one per AZ)."
  value       = aws_subnet.public[*].id
}

output "igw_id" {
  description = "Internet Gateway ID."
  value       = aws_internet_gateway.this.id
}

output "eks_cluster_sg_id" {
  description = "EKS control plane security group ID."
  value       = aws_security_group.eks_cluster.id
}

output "eks_node_sg_id" {
  description = "EKS worker node security group ID."
  value       = aws_security_group.eks_node.id
}

output "rds_sg_id" {
  description = "RDS security group ID."
  value       = aws_security_group.rds.id
}

output "alb_sg_id" {
  description = "ALB security group ID."
  value       = aws_security_group.alb.id
}

output "flow_log_id" {
  description = "VPC flow log ID."
  value       = aws_flow_log.this.id
}

output "flow_log_group_name" {
  description = "CloudWatch log group name for VPC flow logs."
  value       = aws_cloudwatch_log_group.flow_log.name
}

output "flow_log_kms_key_arn" {
  description = "KMS key ARN used to encrypt VPC flow logs."
  value       = aws_kms_key.flow_log.arn
}
