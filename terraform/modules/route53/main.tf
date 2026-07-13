# Route 53 DNS for the platform's APEX domain (e.g. vijaygiduthuri.in).
#
# Two-stage lifecycle (because the apex record targets the Traefik NLB, which
# only exists AFTER Traefik is installed in the cluster):
#
#   Stage 1  (create_apex_record = false, the default)
#     -> creates ONLY the public hosted zone.
#     -> read the `name_servers` output and paste them into GoDaddy
#        (Domain -> Nameservers -> "I'll use my own"). GoDaddy stays the
#        registrar; Route 53 becomes the DNS host.
#
#   Stage 2  (create_apex_record = true, after Traefik/NLB is up)
#     -> looks up the Traefik NLB by its Kubernetes service tag and creates the
#        apex ALIAS A record pointing at it. ALIAS (not CNAME) is the only record
#        type that can legally sit on the apex, and it auto-tracks the NLB's IPs.

resource "aws_route53_zone" "this" {
  name    = var.domain_name
  comment = "Public hosted zone for ${var.domain_name} (banking platform)"

  tags = var.tags
}

# Discover the Traefik NLB by the tag the in-tree AWS cloud provider stamps on it
# (kubernetes.io/service-name = <namespace>/<service>). Only evaluated in stage 2.
data "aws_lb" "traefik" {
  count = var.create_apex_record ? 1 : 0

  tags = {
    "kubernetes.io/service-name" = var.traefik_service_tag
  }
}

# Apex ALIAS A record -> Traefik NLB. ALIAS resolves server-side, so it returns
# the NLB's current IPs and needs no TTL. Re-apply if the NLB is ever recreated.
resource "aws_route53_record" "apex" {
  count = var.create_apex_record ? 1 : 0

  zone_id = aws_route53_zone.this.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = data.aws_lb.traefik[0].dns_name
    zone_id                = data.aws_lb.traefik[0].zone_id
    evaluate_target_health = true
  }
}
