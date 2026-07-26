# ============================================
# VPC Endpoints - Private AWS Service Access
# ============================================

# ============================================
# LOCALS — Dynamic Route Table Associations
# ============================================
# These locals generate ALL route table associations dynamically
# for both S3 and DynamoDB Gateway endpoints.
#
# For each VPC, we associate with:
#   - ALL App route tables (3 per VPC, one per AZ)
#   - The Data route table (1 per VPC)
#
# Total associations per endpoint: 6 VPCs × 4 route tables = 24 associations

locals {
  # Generate app route table associations for all VPCs
  # This loops over each VPC's app route table list and creates
  # one association per AZ: production_app_0, production_app_1, production_app_2
  app_rt_associations = {
    for pair in flatten([
      for key, rt_list in {
        production = aws_route_table.production_app
        hr         = aws_route_table.hr_app
        finance    = aws_route_table.finance_app
        devops     = aws_route_table.devops_app
        staging    = aws_route_table.staging_app
        qa         = aws_route_table.qa_app
      } :
      [
        for idx, rt in rt_list : {
          key      = key
          idx      = idx
          endpoint = key
          rt       = rt.id
        }
      ]


    ]) :
    "${pair.key}_app_${pair.idx}" => {
      endpoint = pair.endpoint
      rt       = pair.rt
    }
  }

  # Generate data route table associations for all VPCs
  data_rt_associations = {
    for key, rt in {
      production = aws_route_table.production_data
      hr         = aws_route_table.hr_data
      finance    = aws_route_table.finance_data
      devops     = aws_route_table.devops_data
      staging    = aws_route_table.staging_data
      qa         = aws_route_table.qa_data
    } :
    "${key}_data" => {
      endpoint = key
      rt       = rt.id
    }
  }

  all_gateway_associations = merge(
    local.app_rt_associations,
    local.data_rt_associations
  )
}

# ============================================
# GATEWAY ENDPOINTS (Free)
# ============================================
# Gateway endpoints work by injecting a route into your route tables.
# They do NOT create ENIs. They are FREE.
# They only work for S3 and DynamoDB.

# S3 Gateway Endpoint — One per VPC
resource "aws_vpc_endpoint" "s3_gateway" {
  for_each = var.create_vpc_endpoints ? {
    production = aws_vpc.production.id
    hr         = aws_vpc.hr.id
    finance    = aws_vpc.finance.id
    devops     = aws_vpc.devops.id
    staging    = aws_vpc.staging.id
    qa         = aws_vpc.qa.id
  } : {}

  vpc_id       = each.value
  service_name = "com.amazonaws.${var.primary_region}.s3"

  tags = merge(local.common_tags, {
    Name = "ABSA-S3-Gateway-Endpoint-${each.key}"
  })
}

# S3 Gateway Route Table Associations
# FIXED: Now associates with ALL App route tables ([0], [1], [2]) + Data route table
# Previously only associated with [0] (af-south-1a only)
resource "aws_vpc_endpoint_route_table_association" "s3_gateway" {
  for_each = var.create_vpc_endpoints ? local.all_gateway_associations : {}

  vpc_endpoint_id = aws_vpc_endpoint.s3_gateway[each.value.endpoint].id
  route_table_id  = each.value.rt
}

# DynamoDB Gateway Endpoint — One per VPC
resource "aws_vpc_endpoint" "dynamodb_gateway" {
  for_each = var.create_vpc_endpoints ? {
    production = aws_vpc.production.id
    hr         = aws_vpc.hr.id
    finance    = aws_vpc.finance.id
    devops     = aws_vpc.devops.id
    staging    = aws_vpc.staging.id
    qa         = aws_vpc.qa.id
  } : {}

  vpc_id       = each.value
  service_name = "com.amazonaws.${var.primary_region}.dynamodb"

  tags = merge(local.common_tags, {
    Name = "ABSA-DynamoDB-Gateway-Endpoint-${each.key}"
  })
}

# DynamoDB Gateway Route Table Associations
# FIXED: Now associates with ALL App route tables ([0], [1], [2]) + Data route table
# Previously only associated with [0] (af-south-1a only)
resource "aws_vpc_endpoint_route_table_association" "dynamodb_gateway" {
  for_each = var.create_vpc_endpoints ? local.all_gateway_associations : {}

  vpc_endpoint_id = aws_vpc_endpoint.dynamodb_gateway[each.value.endpoint].id
  route_table_id  = each.value.rt
}

# ============================================
# INTERFACE ENDPOINTS (Paid)
# ============================================
# Interface endpoints create ENIs (Elastic Network Interfaces)
# in your endpoint subnets. They have private IP addresses.
# They cost ~$0.01/hour per AZ + data transfer.

# Kinesis Streams — Production and Finance only
resource "aws_vpc_endpoint" "kinesis_streams" {
  for_each = var.create_vpc_endpoints ? {
    production = aws_vpc.production.id
    finance    = aws_vpc.finance.id
  } : {}

  vpc_id              = each.value
  service_name        = "com.amazonaws.${var.primary_region}.kinesis-streams"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids = each.key == "production" ? aws_subnet.production_endpoints[*].id : aws_subnet.finance_endpoints[*].id

  security_group_ids = [aws_security_group.vpc_endpoints.id]

  tags = merge(local.common_tags, {
    Name = "ABSA-Kinesis-Interface-Endpoint-${each.key}"
  })
}

# Kinesis Firehose — Production and Finance only
resource "aws_vpc_endpoint" "kinesis_firehose" {
  for_each = var.create_vpc_endpoints ? {
    production = aws_vpc.production.id
    finance    = aws_vpc.finance.id
  } : {}

  vpc_id              = each.value
  service_name        = "com.amazonaws.${var.primary_region}.kinesis-firehose"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids = each.key == "production" ? aws_subnet.production_endpoints[*].id : aws_subnet.finance_endpoints[*].id

  security_group_ids = [aws_security_group.vpc_endpoints.id]

  tags = merge(local.common_tags, {
    Name = "ABSA-Firehose-Interface-Endpoint-${each.key}"
  })
}

# ECR API — Production, DevOps, Staging
resource "aws_vpc_endpoint" "ecr_api" {
  for_each = var.create_vpc_endpoints ? {
    production = aws_vpc.production.id
    devops     = aws_vpc.devops.id
    staging    = aws_vpc.staging.id
  } : {}

  vpc_id              = each.value
  service_name        = "com.amazonaws.${var.primary_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids = each.key == "production" ? aws_subnet.production_endpoints[*].id : (
    each.key == "devops" ? aws_subnet.devops_endpoints[*].id : aws_subnet.staging_endpoints[*].id
  )

  security_group_ids = [aws_security_group.vpc_endpoints.id]

  tags = merge(local.common_tags, {
    Name = "ABSA-ECR-Interface-Endpoint-${each.key}"
  })
}

# ECR DKR — Production, DevOps, Staging
resource "aws_vpc_endpoint" "ecr_dkr" {
  for_each = var.create_vpc_endpoints ? {
    production = aws_vpc.production.id
    devops     = aws_vpc.devops.id
    staging    = aws_vpc.staging.id
  } : {}

  vpc_id              = each.value
  service_name        = "com.amazonaws.${var.primary_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids = each.key == "production" ? aws_subnet.production_endpoints[*].id : (
    each.key == "devops" ? aws_subnet.devops_endpoints[*].id : aws_subnet.staging_endpoints[*].id
  )

  security_group_ids = [aws_security_group.vpc_endpoints.id]

  tags = merge(local.common_tags, {
    Name = "ABSA-ECR-DKR-Interface-Endpoint-${each.key}"
  })
}

# CloudWatch Logs — ALL VPCs
resource "aws_vpc_endpoint" "cloudwatch_logs" {
  for_each = var.create_vpc_endpoints ? {
    production = aws_vpc.production.id
    hr         = aws_vpc.hr.id
    finance    = aws_vpc.finance.id
    devops     = aws_vpc.devops.id
    staging    = aws_vpc.staging.id
    qa         = aws_vpc.qa.id
  } : {}

  vpc_id              = each.value
  service_name        = "com.amazonaws.${var.primary_region}.logs"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids = each.key == "production" ? aws_subnet.production_endpoints[*].id : (
    each.key == "hr" ? aws_subnet.hr_endpoints[*].id : (
      each.key == "finance" ? aws_subnet.finance_endpoints[*].id : (
        each.key == "devops" ? aws_subnet.devops_endpoints[*].id : (
          each.key == "staging" ? aws_subnet.staging_endpoints[*].id : aws_subnet.qa_endpoints[*].id
        )
      )
    )
  )

  security_group_ids = [aws_security_group.vpc_endpoints.id]

  tags = merge(local.common_tags, {
    Name = "ABSA-CloudWatch-Logs-Endpoint-${each.key}"
  })
}

# Secrets Manager — Production and Finance only
resource "aws_vpc_endpoint" "secrets_manager" {
  for_each = var.create_vpc_endpoints ? {
    production = aws_vpc.production.id
    finance    = aws_vpc.finance.id
  } : {}

  vpc_id              = each.value
  service_name        = "com.amazonaws.${var.primary_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids = each.key == "production" ? aws_subnet.production_endpoints[*].id : aws_subnet.finance_endpoints[*].id

  security_group_ids = [aws_security_group.vpc_endpoints.id]

  tags = merge(local.common_tags, {
    Name = "ABSA-Secrets-Manager-Endpoint-${each.key}"
  })
}

# SQS — Production only
resource "aws_vpc_endpoint" "sqs" {
  for_each = var.create_vpc_endpoints ? {
    production = aws_vpc.production.id
  } : {}

  vpc_id              = each.value
  service_name        = "com.amazonaws.${var.primary_region}.sqs"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids         = aws_subnet.production_endpoints[*].id

  security_group_ids = [aws_security_group.vpc_endpoints.id]

  tags = merge(local.common_tags, {
    Name = "ABSA-SQS-Endpoint-${each.key}"
  })
}

# SNS — Production only
resource "aws_vpc_endpoint" "sns" {
  for_each = var.create_vpc_endpoints ? {
    production = aws_vpc.production.id
  } : {}

  vpc_id              = each.value
  service_name        = "com.amazonaws.${var.primary_region}.sns"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids         = aws_subnet.production_endpoints[*].id

  security_group_ids = [aws_security_group.vpc_endpoints.id]

  tags = merge(local.common_tags, {
    Name = "ABSA-SNS-Endpoint-${each.key}"
  })
}

# STS — Production and DevOps only
resource "aws_vpc_endpoint" "sts" {
  for_each = var.create_vpc_endpoints ? {
    production = aws_vpc.production.id
    devops     = aws_vpc.devops.id
  } : {}

  vpc_id              = each.value
  service_name        = "com.amazonaws.${var.primary_region}.sts"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids = each.key == "production" ? aws_subnet.production_endpoints[*].id : aws_subnet.devops_endpoints[*].id

  security_group_ids = [aws_security_group.vpc_endpoints.id]

  tags = merge(local.common_tags, {
    Name = "ABSA-STS-Endpoint-${each.key}"
  })
}

# KMS Interface Endpoint — ALL VPCs (required for encryption/decryption)
resource "aws_vpc_endpoint" "kms" {
  for_each = var.create_vpc_endpoints ? {
    production = aws_vpc.production.id
    hr         = aws_vpc.hr.id
    finance    = aws_vpc.finance.id
    devops     = aws_vpc.devops.id
    staging    = aws_vpc.staging.id
    qa         = aws_vpc.qa.id
  } : {}

  vpc_id              = each.value
  service_name        = "com.amazonaws.${var.primary_region}.kms"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids = each.key == "production" ? aws_subnet.production_endpoints[*].id : (
    each.key == "hr" ? aws_subnet.hr_endpoints[*].id : (
      each.key == "finance" ? aws_subnet.finance_endpoints[*].id : (
        each.key == "devops" ? aws_subnet.devops_endpoints[*].id : (
          each.key == "staging" ? aws_subnet.staging_endpoints[*].id : aws_subnet.qa_endpoints[*].id
        )
      )
    )
  )

  security_group_ids = [aws_security_group.vpc_endpoints.id]

  tags = merge(local.common_tags, {
    Name = "ABSA-KMS-Interface-Endpoint-${each.key}"
  })
}
