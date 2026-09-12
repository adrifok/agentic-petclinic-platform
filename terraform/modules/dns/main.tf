# Module: dns
# Route 53 hosted zone and a DNS-validated ACM wildcard certificate for the
# API Gateway ingress, plus (optionally) the Route 53 alias record pointing
# at the ALB once it exists.
#
# Implements PETPLAT-28 (hosted zone + certificate) and PETPLAT-31 (ALB alias
# record). See docs/technical-spec.md#dns-and-ingress.

locals {
  name_prefix = "${var.project}-${var.environment}"

  # Route 53 record spec (docs/technical-spec.md#dns-and-ingress):
  #   dev:  petclinic-dev.{domain}
  #   prod: petclinic.{domain}
  record_name = var.environment == "prod" ? "petclinic.${var.domain_name}" : "petclinic-${var.environment}.${var.domain_name}"

  zone_id           = var.create_hosted_zone ? aws_route53_zone.this[0].zone_id : data.aws_route53_zone.existing[0].zone_id
  zone_name_servers = var.create_hosted_zone ? aws_route53_zone.this[0].name_servers : data.aws_route53_zone.existing[0].name_servers
}

# ---------------------------------------------------------------------------
# Hosted zone (PETPLAT-28)
#
# Conditional: a domain bought through Route 53 Domain Registration already
# has a hosted zone AWS auto-created and delegated the domain's NS records
# to — creating a second one here would be a dead zone (nothing resolves to
# it) and would strand ACM's DNS validation records where the public
# internet can't see them. Set create_hosted_zone=false in that case (the
# dev wiring does — its domain was registered via Route 53) so this module
# looks up the existing zone instead. Leave it true only for a domain bought
# elsewhere and delegated to a zone this module creates.
# ---------------------------------------------------------------------------

#
# DNSSEC signing and query logging (checkov CKV2_AWS_38/CKV2_AWS_39) are
# intentionally not enabled: DNSSEC needs a dedicated KMS asymmetric CMK
# (~$1/mo) plus a key-signing-key rotation procedure, and query logging
# needs its own CloudWatch log group in us-east-1 for a public zone — both
# real operational cost/complexity this learning project accepts skipping,
# same trade-off reasoning as ADR-0001. Revisit for a real production zone.
resource "aws_route53_zone" "this" {
  count = var.create_hosted_zone ? 1 : 0

  name    = var.domain_name
  comment = "${local.name_prefix} — managed by Terraform (terraform/modules/dns)."

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-zone"
  })
}

# Existing zone lookup — used when create_hosted_zone is false (e.g. the
# zone Route 53 Domain Registration auto-created). Tags on that zone are
# managed outside Terraform (data sources are read-only).
data "aws_route53_zone" "existing" {
  count = var.create_hosted_zone ? 0 : 1

  name         = var.domain_name
  private_zone = false
}

# ---------------------------------------------------------------------------
# ACM certificate — wildcard, DNS-validated (PETPLAT-28)
#
# A single "*.{domain}" wildcard covers both the dev (petclinic-dev.{domain})
# and prod (petclinic.{domain}) records without per-environment SANs. Region
# matches the provider's (eu-central-1, same as the ALB) — this is a
# regional cert for ALB listeners, not a CloudFront cert, so it does not need
# us-east-1.
# ---------------------------------------------------------------------------

resource "aws_acm_certificate" "this" {
  domain_name       = "*.${var.domain_name}"
  validation_method = "DNS"

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-cert"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id         = local.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

# ---------------------------------------------------------------------------
# ALB alias record (PETPLAT-31) — off by default, see variables.tf.
# ---------------------------------------------------------------------------

# checkov:skip=CKV2_AWS_23: alias target is an ALB the AWS Load Balancer
# Controller creates from the Ingress resource, not a Terraform aws_lb —
# there is no in-state resource for checkov to see a reference to.
resource "aws_route53_record" "alb_alias" {
  count = var.create_alb_record ? 1 : 0

  zone_id = local.zone_id
  name    = local.record_name
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }

  lifecycle {
    precondition {
      condition     = var.alb_dns_name != "" && var.alb_zone_id != ""
      error_message = "alb_dns_name and alb_zone_id must both be set when create_alb_record is true."
    }
  }
}
