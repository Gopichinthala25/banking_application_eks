variable "domain_name" {
  description = "Apex domain to host in Route 53 (e.g. vijaygiduthuri.in). No subdomain."
  type        = string
}

variable "create_apex_record" {
  description = "Stage 2 toggle: create the apex ALIAS record -> Traefik NLB. Leave false until Traefik (the NLB) is installed, then set true and re-apply."
  type        = bool
  default     = false
}

variable "traefik_service_tag" {
  description = "kubernetes.io/service-name tag on the Traefik NLB (<namespace>/<service>). Used to discover the NLB in stage 2."
  type        = string
  default     = "traefik/traefik"
}

variable "tags" {
  description = "Common tags."
  type        = map(string)
  default     = {}
}
