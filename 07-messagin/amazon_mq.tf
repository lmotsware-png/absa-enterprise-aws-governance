# ============================================
# Amazon MQ — Legacy System Integration
# ============================================

resource "aws_mq_broker" "legacy_integration" {
  count = var.enable_amazon_mq ? 1 : 0

  broker_name        = var.mq_broker_name
  engine_type        = var.mq_engine_type
  engine_version     = var.mq_engine_version
  host_instance_type = var.mq_instance_type
  deployment_mode    = "ACTIVE_STANDBY_MULTI_AZ"
  publicly_accessible = false

  user {
    username = var.mq_username
    password = random_password.mq.result
  }

  configuration {
    id       = aws_mq_configuration.main.id
    revision = aws_mq_configuration.main.latest_revision
  }

  subnet_ids = local.data_subnet_ids

  security_groups = [local.app_security_group_id]

  encryption_options {
    kms_key_id        = local.kms_s3_arn
    use_aws_owned_key = false
  }

  logs {
    general = true
    audit   = true
  }

  maintenance_window_start_time {
    day_of_week = "SUNDAY"
    time_of_day = "03:00"
    time_zone   = "Africa/Johannesburg"
  }

  tags = merge(local.common_tags, {
    Name = var.mq_broker_name
  })
}

# Amazon MQ Configuration
resource "aws_mq_configuration" "main" {
  description    = "ABSA Legacy Integration Configuration"
  engine_type    = var.mq_engine_type
  engine_version = var.mq_engine_version
  name           = "absa-legacy-config"

  data = <<-XML
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<broker xmlns="http://activemq.apache.org/schema/core">
  <destinationPolicy>
    <policyMap>
      <policyEntries>
        <policyEntry queue=">" producerFlowControl="true" memoryLimit="1gb"/>
        <policyEntry topic=">" producerFlowControl="true" memoryLimit="1gb"/>
      </policyEntries>
    </policyMap>
  </destinationPolicy>
  <plugins>
    <authorizationPlugin>
      <map>
        <authorizationMap>
          <authorizationEntries>
            <authorizationEntry queue=">" read="admins" write="admins" admin="admins"/>
            <authorizationEntry topic=">" read="admins" write="admins" admin="admins"/>
          </authorizationEntries>
        </authorizationMap>
      </map>
    </authorizationPlugin>
  </plugins>
</broker>
XML
}

resource "random_password" "mq" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
  min_special      = 4
  min_upper        = 4
  min_lower        = 4
  min_numeric      = 4
}