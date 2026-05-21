# ============================================
# VPC Endpoints - Private AWS Service Access
# ============================================

# Gateway Endpoints (Free) - S3 and DynamoDB
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

resource "aws_vpc_endpoint_route_table_association" "s3_gateway" {
  for_each = var.create_vpc_endpoints ? {
    production_app  = { endpoint = "production", rt = aws_route_table.production_app[0].id }
    production_data = { endpoint = "production", rt = aws_route_table.production_data.id }
    hr_app          = { endpoint = "hr", rt = aws_route_table.hr_app[0].id }
    hr_data         = { endpoint = "hr", rt = aws_route_table.hr_data.id }
    finance_app     = { endpoint = "finance", rt = aws_route_table.finance_app[0].id }
    finance_data    = { endpoint = "finance", rt = aws_route_table.finance_data.id }
    devops_app      = { endpoint = "devops", rt = aws_route_table.devops_app[0].id }
    devops_data     = { endpoint = "devops", rt = aws_route_table.devops_data.id }
    staging_app     = { endpoint = "staging", rt = aws_route_table.staging_app[0].id }
    staging_data    = { endpoint = "staging", rt = aws_route_table.staging_data.id }
    qa_app          = { endpoint = "qa", rt = aws_route_table.qa_app[0].id }
    qa_data         = { endpoint = "qa", rt = aws_route_table.qa_data.id }
  } : {}

  vpc_endpoint_id = aws_vpc_endpoint.s3_gateway[each.value.endpoint].id
  route_table_id  = each.value.rt
}

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

resource "aws_vpc_endpoint_route_table_association" "dynamodb_gateway" {
  for_each = var.create_vpc_endpoints ? {
    production_app  = { endpoint = "production", rt = aws_route_table.production_app[0].id }
    production_data = { endpoint = "production", rt = aws_route_table.production_data.id }
    hr_app          = { endpoint = "hr", rt = aws_route_table.hr_app[0].id }
    hr_data         = { endpoint = "hr", rt = aws_route_table.hr_data.id }
    finance_app     = { endpoint = "finance", rt = aws_route_table.finance_app[0].id }
    finance_data    = { endpoint = "finance", rt = aws_route_table.finance_data.id }
    devops_app      = { endpoint = "devops", rt = aws_route_table.devops_app[0].id }
    devops_data     = { endpoint = "devops", rt = aws_route_table.devops_data.id }
    staging_app     = { endpoint = "staging", rt = aws_route_table.staging_app[0].id }
    staging_data    = { endpoint = "staging", rt = aws_route_table.staging_data.id }
    qa_app          = { endpoint = "qa", rt = aws_route_table.qa_app[0].id }
    qa_data         = { endpoint = "qa", rt = aws_route_table.qa_data.id }
  } : {}

  vpc_endpoint_id = aws_vpc_endpoint.dynamodb_gateway[each.value.endpoint].id
  route_table_id  = each.value.rt
}

# Interface Endpoints (Paid) - For all other AWS services
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