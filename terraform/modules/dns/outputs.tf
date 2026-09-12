# Module: dns — outputs
# See docs/technical-spec.md#terraform-modules.

output "zone_id" {
  description = "Route 53 hosted zone ID."
  value       = aws_route53_zone.this.zone_id
}

output "name_servers" {
  description = "Route 53 hosted zone name servers — delegate the domain to these at the registrar."
  value       = aws_route53_zone.this.name_servers
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
