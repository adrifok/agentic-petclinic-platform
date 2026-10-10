# Module: karpenter — outputs
# See docs/technical-spec.md#module-karpenter.

output "karpenter_role_arn" {
  description = "Karpenter controller IRSA role ARN — annotate the kube-system/karpenter ServiceAccount with it."
  value       = aws_iam_role.controller.arn
}

output "karpenter_queue_name" {
  description = "SQS interruption queue name — Karpenter Helm value settings.interruptionQueue."
  value       = aws_sqs_queue.interruption.name
}

output "karpenter_instance_profile_name" {
  description = "Instance profile for Karpenter-launched nodes — referenced by spec.instanceProfile in the EC2NodeClass."
  value       = aws_iam_instance_profile.node.name
}
