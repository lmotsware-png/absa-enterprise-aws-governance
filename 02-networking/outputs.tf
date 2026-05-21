# ============================================
# Outputs for Week 3 (Security) and Week 4 (Production)
# ============================================

output "transit_gateway_id" {
  value       = aws_ec2_transit_gateway.main.id
  description = "Transit Gateway ID for cross-account RAM shares"
}

output "transit_gateway_arn" {
  value       = aws_ec2_transit_gateway.main.arn
  description = "Transit Gateway ARN"
}

output "tgw_route_table_ids" {
  value = {
    production_to_shared = aws_ec2_transit_gateway_route_table.production_to_shared.id
    shared_to_production = aws_ec2_transit_gateway_route_table.shared_to_production.id
    finance_to_shared    = aws_ec2_transit_gateway_route_table.finance_to_shared.id
    dev_to_shared        = aws_ec2_transit_gateway_route_table.dev_to_shared.id
    staging_to_shared    = aws_ec2_transit_gateway_route_table.staging_to_shared.id
  }
  description = "TGW route table IDs for dynamic routing updates"
}

output "vpc_ids" {
  value = {
    production = aws_vpc.production.id
    hr         = aws_vpc.hr.id
    finance    = aws_vpc.finance.id
    devops     = aws_vpc.devops.id
    staging    = aws_vpc.staging.id
    qa         = aws_vpc.qa.id
  }
  description = "VPC IDs for all environments"
}

output "vpc_cidrs" {
  value = {
    production = var.vpc_cidrs.production
    hr         = var.vpc_cidrs.hr
    finance    = var.vpc_cidrs.finance
    devops     = var.vpc_cidrs.devops
    staging    = var.vpc_cidrs.staging
    qa         = var.vpc_cidrs.qa
  }
  description = "VPC CIDR blocks for security group rules"
}

output "subnet_ids" {
  value = {
    production_public    = aws_subnet.production_public[*].id
    production_app       = aws_subnet.production_app[*].id
    production_data      = aws_subnet.production_data[*].id
    production_endpoints = aws_subnet.production_endpoints[*].id
    hr_app               = aws_subnet.hr_app[*].id
    hr_data              = aws_subnet.hr_data[*].id
    finance_app          = aws_subnet.finance_app[*].id
    finance_data         = aws_subnet.finance_data[*].id
    devops_app           = aws_subnet.devops_app[*].id
    devops_data          = aws_subnet.devops_data[*].id
    staging_app          = aws_subnet.staging_app[*].id
    staging_data         = aws_subnet.staging_data[*].id
    qa_app               = aws_subnet.qa_app[*].id
    qa_data              = aws_subnet.qa_data[*].id
  }
  description = "Subnet IDs for resource placement"
}

output "security_group_ids" {
  value = {
    vpc_endpoints = aws_security_group.vpc_endpoints.id
    alb           = aws_security_group.alb.id
    baseline_app  = aws_security_group.baseline_app.id
    baseline_data = aws_security_group.baseline_data.id
  }
  description = "Security group IDs for Week 4 application deployment"
}

output "nat_gateway_ips" {
  value = var.create_nat_gateways ? {
    production = aws_eip.production_nat[*].public_ip
    hr         = aws_eip.hr_nat[*].public_ip
    finance    = aws_eip.finance_nat[*].public_ip
    devops     = aws_eip.devops_nat[*].public_ip
    staging    = aws_eip.staging_nat[*].public_ip
    qa         = aws_eip.qa_nat[*].public_ip
  } : {}
  description = "NAT Gateway public IPs for external firewall allow-listing"
  sensitive   = false
}