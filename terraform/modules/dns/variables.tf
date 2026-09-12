# Module: dns — input variables
# See docs/technical-spec.md#dns-and-ingress and #terraform-modules.

variable "project" {
  description = "Project name, used in resource naming."
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Deployment environment (dev or prod) — selects the record name: petclinic-{env}.{domain_name} for dev, petclinic.{domain_name} for prod."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be \"dev\" or \"prod\"."
  }
}

variable "domain_name" {
  description = "Apex domain for the Route 53 hosted zone (e.g. \"example.com\"). You must own this domain and delegate it to the zone's name servers (module output name_servers) for DNS validation and public resolution to work."
  type        = string

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,}$", var.domain_name))
    error_message = "domain_name must be a valid lowercase domain name, e.g. \"example.com\"."
  }
}

variable "create_hosted_zone" {
  description = "Whether this module creates the Route 53 hosted zone. Set false when domain_name was registered via Route 53 Domain Registration — that auto-creates a hosted zone and delegates the domain's NS records to it already; creating a second one here would be a dead zone that ACM's DNS validation records would be stranded in. When false, the module looks up the existing zone by name instead."
  type        = bool
  default     = true
}

# --- ALB alias record (PETPLAT-31) ---
#
# Left disabled by default: the ALB doesn't exist until the AWS Load Balancer
# Controller (PETPLAT-29) and the Ingress resource (PETPLAT-30) are deployed,
# which happens after this module's first apply (PETPLAT-32 wires the zone +
# certificate only). Once the Ingress is applied, get the ALB's hostname/zone
# with:
#   kubectl get ingress api-gateway -n petclinic-{env} \
#     -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
#   aws elbv2 describe-load-balancers --region eu-central-1 \
#     --query "LoadBalancers[?DNSName=='<hostname-from-above>'].CanonicalHostedZoneId" --output text
# then re-apply with create_alb_record=true and both values set.

variable "create_alb_record" {
  description = "Whether to create the Route 53 alias A record pointing at the ALB. False until the ALB exists (see comment above) — PETPLAT-31."
  type        = bool
  default     = false
}

variable "alb_dns_name" {
  description = "DNS name of the ALB created by the AWS Load Balancer Controller for the Ingress. Required when create_alb_record is true."
  type        = string
  default     = ""
}

variable "alb_zone_id" {
  description = "Canonical hosted zone ID of the ALB (from `aws elbv2 describe-load-balancers`, NOT the Route 53 zone_id output of this module). Required when create_alb_record is true."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags merged into every resource (Project/Environment/ManagedBy come from provider default_tags)."
  type        = map(string)
  default     = {}
}
