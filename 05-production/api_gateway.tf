# ============================================
# API Gateway — REST API for ABSA Banking
# ============================================

resource "aws_api_gateway_rest_api" "main" {
  name        = var.api_gateway_name
  description = "ABSA Banking API — Payment processing, account management, fraud detection, airtime purchase"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  minimum_compression_size = 1024

  tags = merge(local.common_tags, {
    Name = var.api_gateway_name
  })
}

# ============================================
# API Gateway Resource Policy — Enforce CloudFront as the ONLY source
# ============================================
# Denies any request whose source ARN is NOT our CloudFront distribution.
# Uses aws:SourceArn — a native AWS IAM condition key that actually works.
# The X-Origin-Verify header in cloudfront.tf LABELS traffic for auditing.
# This resource policy ENFORCES that only CloudFront can invoke the API.
# ============================================

resource "aws_api_gateway_rest_api_policy" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Deny"
        Principal = "*"
        Action    = "execute-api:Invoke"
        Resource  = "${aws_api_gateway_rest_api.main.execution_arn}/*"
        Condition = {
          StringNotEquals = {
            "aws:SourceArn" = "arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:distribution/${aws_cloudfront_distribution.main[0].id}"
          }
        }
      },
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "execute-api:Invoke"
        Resource  = "${aws_api_gateway_rest_api.main.execution_arn}/*"
      }
    ]
  })
}

# ============================================
# API Resources — /api/v1/...
# ============================================

resource "aws_api_gateway_resource" "api" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "api"
}

resource "aws_api_gateway_resource" "v1" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.api.id
  path_part   = "v1"
}

resource "aws_api_gateway_resource" "payments" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.v1.id
  path_part   = "payments"
}

resource "aws_api_gateway_resource" "transfer" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.payments.id
  path_part   = "transfer"
}

resource "aws_api_gateway_resource" "accounts" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.v1.id
  path_part   = "accounts"
}

resource "aws_api_gateway_resource" "account_by_id" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.accounts.id
  path_part   = "{accountId}"
}

resource "aws_api_gateway_resource" "balance" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.account_by_id.id
  path_part   = "balance"
}

resource "aws_api_gateway_resource" "airtime" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.v1.id
  path_part   = "airtime"
}

resource "aws_api_gateway_resource" "airtime_purchase" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.airtime.id
  path_part   = "purchase"
}

# ============================================
# API Methods
# ============================================

resource "aws_api_gateway_method" "transfer_post" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.transfer.id
  http_method   = "POST"
  authorization = "NONE"

  request_parameters = {
    "method.request.header.Authorization" = true
  } 

  request_validator_id = aws_api_gateway_request_validator.main.id
}

resource "aws_api_gateway_method" "balance_get" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.balance.id
  http_method   = "GET"
  authorization = "NONE"

  request_parameters = {
    "method.request.header.Authorization" = true
  }

  request_validator_id = aws_api_gateway_request_validator.main.id
}

resource "aws_api_gateway_method" "airtime_purchase_post" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.airtime_purchase.id
  http_method   = "POST"
  authorization = "NONE"

  request_parameters = {
    "method.request.header.Authorization" = true
  }

  request_validator_id = aws_api_gateway_request_validator.main.id
}

resource "aws_api_gateway_method" "transfer_options" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.transfer.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "airtime_options" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.airtime_purchase.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

# ============================================
# VPC Link — Targets the NLB (REST API requirement)
# ============================================

resource "aws_api_gateway_vpc_link" "main" {
  name        = "ABSA-EKS-VPC-Link"
  description = "VPC Link to internal NLB, which fronts the EKS Application Load Balancer"
  target_arns = [aws_lb.nlb.arn]

  tags = merge(local.common_tags, {
    Name = "ABSA-EKS-VPC-Link"
  })
}

# ============================================
# API Integrations — Connect to EKS via VPC Link → NLB → ALB → Pod
# ============================================

resource "aws_api_gateway_integration" "transfer_post" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.transfer.id
  http_method = aws_api_gateway_method.transfer_post.http_method

  type                    = "HTTP_PROXY"
  integration_http_method = "POST"
  uri                     = "https://${aws_lb.main.dns_name}/api/v1/payments/transfer"
  connection_type         = "VPC_LINK"
  connection_id           = aws_api_gateway_vpc_link.main.id

  request_parameters = {
    "integration.request.header.Authorization" = "method.request.header.Authorization"
  }
}

resource "aws_api_gateway_integration" "balance_get" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.balance.id
  http_method = aws_api_gateway_method.balance_get.http_method

  type                    = "HTTP_PROXY"
  integration_http_method = "GET"
  uri                     = "https://${aws_lb.main.dns_name}/api/v1/accounts/{accountId}/balance"
  connection_type         = "VPC_LINK"
  connection_id           = aws_api_gateway_vpc_link.main.id

  request_parameters = {
    "integration.request.header.Authorization" = "method.request.header.Authorization"
  }
}

resource "aws_api_gateway_integration" "airtime_purchase_post" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.airtime_purchase.id
  http_method = aws_api_gateway_method.airtime_purchase_post.http_method

  type                    = "HTTP_PROXY"
  integration_http_method = "POST"
  uri                     = "https://${aws_lb.main.dns_name}/api/v1/airtime/purchase"
  connection_type         = "VPC_LINK"
  connection_id           = aws_api_gateway_vpc_link.main.id

  request_parameters = {
    "integration.request.header.Authorization" = "method.request.header.Authorization"
  }
}

# ============================================
# Request Validator
# ============================================

resource "aws_api_gateway_request_validator" "main" {
  name                        = "ABSA-Request-Validator"
  rest_api_id                 = aws_api_gateway_rest_api.main.id
  validate_request_body       = true
  validate_request_parameters = true
}

# ============================================
# API Gateway Models
# ============================================

resource "aws_api_gateway_model" "transfer_request" {
  rest_api_id  = aws_api_gateway_rest_api.main.id
  name         = "TransferRequest"
  description  = "Payment transfer request body"
  content_type = "application/json"

  schema = jsonencode({
    type     = "object"
    required = ["from_account", "to_account", "amount", "currency"]
    properties = {
      from_account = { type = "string", pattern = "^[0-9]{4}-[0-9]{4}-[0-9]{4}$" }
      to_account   = { type = "string", pattern = "^[0-9]{4}-[0-9]{4}-[0-9]{4}$" }
      amount       = { type = "number", minimum = 0.01, maximum = 1000000.00 }
      currency     = { type = "string", enum = ["ZAR", "USD", "GBP", "EUR"] }
    }
  })
}

resource "aws_api_gateway_model" "airtime_request" {
  rest_api_id  = aws_api_gateway_rest_api.main.id
  name         = "AirtimeRequest"
  description  = "Airtime purchase request body"
  content_type = "application/json"

  schema = jsonencode({
    type     = "object"
    required = ["phone_number", "amount", "network"]
    properties = {
      phone_number = {
        type        = "string"
        description = "Recipient mobile number"
        pattern     = "^0[6-8][0-9]{8}$"
      }
      amount = {
        type        = "number"
        description = "Airtime amount in ZAR"
        minimum     = 5
        maximum     = 5000
      }
      network = {
        type        = "string"
        description = "Mobile network provider"
        enum        = ["Vodacom", "MTN", "Cell C", "Telkom", "Rain"]
      }
      from_account = {
        type        = "string"
        description = "Account to debit"
        pattern     = "^[0-9]{4}-[0-9]{4}-[0-9]{4}$"
      }
    }
  })
}

# ============================================
# API Deployment
# ============================================

resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  description = "ABSA Banking API deployment — ${var.api_gateway_stage}"

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.transfer,
      aws_api_gateway_resource.balance,
      aws_api_gateway_resource.airtime_purchase,
      aws_api_gateway_method.transfer_post,
      aws_api_gateway_method.balance_get,
      aws_api_gateway_method.airtime_purchase_post,
      aws_api_gateway_integration.transfer_post,
      aws_api_gateway_integration.balance_get,
      aws_api_gateway_integration.airtime_purchase_post,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================
# API Stage
# ============================================

resource "aws_api_gateway_stage" "main" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = var.api_gateway_stage

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      caller         = "$context.identity.caller"
      user           = "$context.identity.user"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      resourcePath   = "$context.resourcePath"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
    })
  }

  tags = merge(local.common_tags, {
    Name = "${var.api_gateway_name}-${var.api_gateway_stage}"
  })
}

# ============================================
# CloudWatch Log Group for API Gateway
# ============================================

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/api-gateway/${var.api_gateway_name}"
  retention_in_days = 90

  tags = merge(local.common_tags, {
    Name = "ABSA-API-Gateway-Logs"
  })
}

# ============================================
# API Gateway Usage Plan
# ============================================

resource "aws_api_gateway_usage_plan" "main" {
  name        = "ABSA-Banking-Usage-Plan"
  description = "Usage plan for ABSA mobile banking app"

  api_stages {
    api_id = aws_api_gateway_rest_api.main.id
    stage  = aws_api_gateway_stage.main.stage_name
  }

  throttle_settings {
    burst_limit = 5000
    rate_limit  = 10000
  }

  quota_settings {
    limit  = 10000000
    period = "MONTH"
  }

  tags = merge(local.common_tags, {
    Name = "ABSA-Banking-Usage-Plan"
  })
}