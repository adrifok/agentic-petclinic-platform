# Module: github-oidc — outputs

output "role_arn" {
  description = "IAM role ARN for aws-actions/configure-aws-credentials role-to-assume (set as AWS_ROLE_ARN secret in the app repo)."
  value       = aws_iam_role.github_actions.arn
}

output "role_name" {
  description = "IAM role name."
  value       = aws_iam_role.github_actions.name
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider (created here or passed in)."
  value       = local.oidc_provider_arn
}

output "trusted_subject" {
  description = "The exact token.actions.githubusercontent.com:sub value the role trusts."
  value       = local.github_sub_subject
}
