variable "primary_region" {
  description = "Primary AWS region for ABSA operations"
  type        = string
  default     = "eu-west-1"
}

variable "dr_region" {
  description = "Disaster Recovery region"
  type        = string
  default     = "af-south-1"
}

variable "environment" {
  description = "Deployment environment identifier"
  type        = string
  default     = "Production"
}

variable "vpc_cidrs" {
  description = "CIDR blocks for all ABSA VPCs"
  type = object({
    production = string
    hr         = string
    finance    = string
    devops     = string
    staging    = string
    qa         = string
  })
  default = {
    production = "10.1.0.0/16"
    hr         = "10.2.0.0/16"
    finance    = "10.3.0.0/16"
    devops     = "10.4.0.0/16"
    staging    = "10.5.0.0/16"
    qa         = "10.6.0.0/16"
  }
}

variable "availability_zones" {
  description = "AZs to deploy subnets into"
  type        = list(string)
  default     = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
}

variable "transit_gateway" {
  description = "TGW configuration"
  type = object({
    amazon_side_asn                 = number
    auto_accept_shared_attachments  = string
    default_route_table_association = string
    default_route_table_propagation = string
    dns_support                     = string
    vpn_ecmp_support                = string
  })
  default = {
    amazon_side_asn                 = 64512
    auto_accept_shared_attachments  = "enable"
    default_route_table_association = "disable"
    default_route_table_propagation = "disable"
    dns_support                     = "enable"
    vpn_ecmp_support                = "enable"
  }
}

variable "create_nat_gateways" {
  description = "Whether to create NAT Gateways (cost ~$32/month each)"
  type        = bool
  default     = true
}

variable "create_vpc_endpoints" {
  description = "Whether to create VPC endpoints (Interface endpoints cost ~$7/month each per AZ)"
  type        = bool
  default     = true
}