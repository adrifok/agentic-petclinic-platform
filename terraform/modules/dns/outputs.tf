# Module: dns — outputs
# See docs/technical-spec.md#terraform-modules.

output "zone_id" {
  description = "Route 53 hosted zone ID (created by this module, or looked up if create_hosted_zone is false)."
  value       = local.zone_id
}

output "name_servers" {
  description = "Route 53 hosted zone name servers. Only useful to delegate at the registrar when create_hosted_zone is true — when false (e.g. Route 53 Domain Registration), the registrar is already delegated to this same zone."
  value       = local.zone_name_servers
}

output "certificate_arn" {
  description = "Validated ACM certificate ARN (wildcard *.{domain_name}) — pass to the Ingress's alb.ingress.kubernetes.io/certificate-arn annotation."
  value       = aws_acm_certificate_validation.this.certificate_arn
}

output "record_name" {
  description = "FQDN this environment's ALB alias record uses (petclinic-{env}.{domain} for dev, petclinic.{domain} for prod), whether or not create_alb_record has been enabled yet."
  value       = local.record_name
}

output "alb_record_fqdn" {
  description = "FQDN of the created ALB alias record, or null if create_alb_record is false (PETPLAT-31 not yet wired)."
  value       = try(aws_route53_record.alb_alias[0].fqdn, null)
}
