# Module: ecr — outputs
# See docs/technical-spec.md#terraform-modules.

output "repository_urls" {
  description = "Map of service_name -> ECR repository URL (push/pull target)."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
}

output "repository_arns" {
  description = "Map of service_name -> ECR repository ARN."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.arn }
}

output "repository_names" {
  description = "Map of service_name -> full ECR repository name (petclinic-{env}/{service})."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.name }
}
