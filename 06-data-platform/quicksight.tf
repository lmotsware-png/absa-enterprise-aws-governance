# ============================================
# QuickSight — Business Intelligence Dashboards
# ============================================

# QuickSight Account Subscription
resource "aws_quicksight_account_subscription" "main" {
  account_name        = "ABSA-Enterprise"
  authentication_method = "IAM_AND_QUICKSIGHT"
  edition             = "ENTERPRISE"
  notification_email  = "analytics@absa.co.za"
}

# QuickSight Data Source — Athena
resource "aws_quicksight_data_source" "athena" {
  data_source_id = "absa-athena-datasource"
  name           = "ABSA Athena Analytics"

  parameters {
    athena {
      work_group = aws_athena_workgroup.main.name
    }
  }

  type = "ATHENA"

  permission {
    principal = aws_quicksight_group.analysts.arn
    actions = [
      "quicksight:DescribeDataSource",
      "quicksight:DescribeDataSourcePermissions",
      "quicksight:PassDataSource"
    ]
  }

  depends_on = [aws_quicksight_account_subscription.main]
}

# QuickSight Data Source — Redshift
resource "aws_quicksight_data_source" "redshift" {
  data_source_id = "absa-redshift-datasource"
  name           = "ABSA Data Warehouse"

  parameters {
    redshift {
      database = var.redshift_database_name
      host     = aws_redshift_cluster.main[0].endpoint
      port     = 5439
    }
  }

  type = "REDSHIFT"

  permission {
    principal = aws_quicksight_group.analysts.arn
    actions = [
      "quicksight:DescribeDataSource",
      "quicksight:DescribeDataSourcePermissions",
      "quicksight:PassDataSource"
    ]
  }

  depends_on = [aws_quicksight_account_subscription.main]
}

# QuickSight Group — Analysts
resource "aws_quicksight_group" "analysts" {
  group_name  = "ABSA-Analysts"
  description = "Data analysts with access to dashboards"

  depends_on = [aws_quicksight_account_subscription.main]
}

# QuickSight Dashboard — Transaction Overview
resource "aws_quicksight_dashboard" "transaction_overview" {
  dashboard_id = "absa-transaction-overview"
  name         = "ABSA Transaction Overview"

  version_description = "Initial version — Daily transaction metrics"

  source_entity {
    source_template {
      arn = "arn:aws:quicksight:af-south-1:${data.aws_caller_identity.current.account_id}:template/transaction-template"
      data_set_references {
        data_set_arn         = aws_quicksight_data_set.transactions.arn
        data_set_placeholder = "transactions"
      }
    }
  }

  permissions {
    principal = aws_quicksight_group.analysts.arn
    actions = [
      "quicksight:DescribeDashboard",
      "quicksight:QueryDashboard",
      "quicksight:ListDashboardVersions"
    ]
  }

  depends_on = [aws_quicksight_account_subscription.main]
}

# QuickSight Data Set — Transactions
resource "aws_quicksight_data_set" "transactions" {
  data_set_id = "absa-transactions"
  name        = "ABSA Transactions"
  import_mode = "SPICE"

  physical_table_map {
    physical_table_map_id = "transactions"
    relational_table {
      data_source_arn = aws_quicksight_data_source.athena.arn
      name            = "transactions"
      input_columns {
        name = "transaction_id"
        type = "STRING"
      }
      input_columns {
        name = "amount"
        type = "DECIMAL"
      }
      input_columns {
        name = "fraud_score"
        type = "INTEGER"
      }
      input_columns {
        name = "location"
        type = "STRING"
      }
      input_columns {
        name = "timestamp"
        type = "DATETIME"
      }
    }
  }

  permissions {
    principal = aws_quicksight_group.analysts.arn
    actions = [
      "quicksight:DescribeDataSet",
      "quicksight:DescribeDataSetPermissions",
      "quicksight:PassDataSet"
    ]
  }

  depends_on = [aws_quicksight_account_subscription.main]
}