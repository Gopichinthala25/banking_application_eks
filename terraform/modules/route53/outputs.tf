output "zone_id" {
  description = "Route 53 hosted zone ID for the apex domain."
  value       = aws_route53_zone.this.zone_id
}

output "name_servers" {
  description = "The 4 Route 53 nameservers to set at GoDaddy (delegation)."
  value       = aws_route53_zone.this.name_servers
}

output "apex_fqdn" {
  description = "The apex ALIAS record FQDN (empty until create_apex_record = true)."
  value       = try(aws_route53_record.apex[0].fqdn, "")
}
