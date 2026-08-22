# ============================================
# Application Load Balancer — Traffic Routing to EKS Pods
# ============================================

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "ABSA-Production-ALB"
  internal           = true   # Private ALB — only reachable via the NLB below
  load_balancer_type = "application"
  security_groups    = [local.alb_security_group_id]
  subnets            = local.public_subnet_ids

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.bucket
    prefix  = "alb-logs"
    enabled = true
  }

  tags = merge(local.common_tags, {
    Name = "ABSA-Production-ALB"
  })
}

# ============================================
# Network Load Balancer — Required by API Gateway REST API VPC Links
# REST API VPC Links can only target an NLB, never an ALB directly.
# This NLB sits in front of the ALB using AWS's native "ALB target type" feature.
# ============================================

resource "aws_lb" "nlb" {
  name               = "ABSA-Production-NLB"
  internal           = true
  load_balancer_type = "network"
  subnets            = local.app_subnet_ids

  tags = merge(local.common_tags, {
    Name = "ABSA-Production-NLB"
  })
}

# Target group of type "alb" — registers the ALB itself as a single target
resource "aws_lb_target_group" "alb_target" {
  name        = "ABSA-NLB-ALB-Target"
  target_type = "alb"
  port        = 443
  protocol    = "TCP"
  vpc_id      = local.vpc_id

  health_check {
    enabled             = true
    protocol            = "HTTPS"
    port                = "443"
    path                = "/health"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = merge(local.common_tags, {
    Name = "ABSA-NLB-ALB-Target-Group"
  })
}

resource "aws_lb_target_group_attachment" "alb_target" {
  target_group_arn = aws_lb_target_group.alb_target.arn
  target_id        = aws_lb.main.arn
  port             = 443

  depends_on = [aws_lb_listener.https]
}

resource "aws_lb_listener" "nlb_listener" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = 443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_target.arn
  }
}

# ============================================
# Target Groups — Payment API and Fraud Detection pods
# ============================================

resource "aws_lb_target_group" "payment_api" {
  name        = "ABSA-Payment-API-TG"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200-299"
  }

  slow_start = 30

  stickiness {
    type            = "lb_cookie"
    enabled         = true
    cookie_duration = 86400
  }

  tags = merge(local.common_tags, {
    Name = "ABSA-Payment-API-Target-Group"
  })

  depends_on = [aws_lb.main]
}

resource "aws_lb_target_group" "fraud_detection" {
  name        = "ABSA-Fraud-Detection-TG"
  port        = 8081
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200-299"
  }

  tags = merge(local.common_tags, {
    Name = "ABSA-Fraud-Detection-Target-Group"
  })

  depends_on = [aws_lb.main]
}

# ============================================
# Listeners and Rules
# ============================================

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.main.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.payment_api.arn
  }

  depends_on = [aws_lb_target_group.payment_api]
}

resource "aws_lb_listener_rule" "payment_api" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.payment_api.arn
  }

  condition {
    path_pattern {
      values = ["/api/v1/payments/*"]
    }
  }
}

resource "aws_lb_listener_rule" "fraud_detection" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.fraud_detection.arn
  }

  condition {
    path_pattern {
      values = ["/api/v1/fraud/*"]
    }
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = 443
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# ============================================
# ACM Certificate — With DNS validation
# ============================================

resource "aws_acm_certificate" "main" {
  domain_name       = var.cloudfront_domain_name
  validation_method = "DNS"

  subject_alternative_names = [
    "*.${var.cloudfront_domain_name}"
  ]

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, {
    Name = "ABSA-ACM-Certificate"
  })
}

data "aws_route53_zone" "main" {
  name         = "absa.co.za"
  private_zone = false
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = data.aws_route53_zone.main.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "main" {
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# ============================================
# S3 Bucket for ALB Access Logs
# ============================================

resource "aws_s3_bucket" "alb_logs" {
  bucket        = "absa-alb-access-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = false

  tags = merge(local.common_tags, {
    Name = "ABSA-ALB-Access-Logs"
  })
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Using service principal — works in any region, including af-south-1
resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSLogDeliveryWrite"
        Effect = "Allow"
        Principal = {
          Service = "logdelivery.elasticloadbalancing.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.alb_logs.arn}/alb-logs/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Sid    = "AWSLogDeliveryAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "logdelivery.elasticloadbalancing.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.alb_logs.arn
      }
    ]
  })
}

data "aws_caller_identity" "current" {}