# ============================================
# Outputs — Values for Weeks 7, 8, and 9
# ============================================

# Kinesis
output "kinesis_stream_arn" {
  value       = aws_kinesis_stream.transactions.arn
  description = "Kinesis Data Stream ARN for Week 7 messaging integration"
}

output "kinesis_stream_name" {
  value       = aws_kinesis_stream.transactions.name
  description = "Kinesis Data Stream name for application configuration"
}

output "firehose_delivery_stream_arn" {
  value       = aws_kinesis_firehose_delivery_stream.transactions_to_s3.arn
  description = "Firehose delivery stream ARN"
}

# S3
output "firehose_bucket_arn" {
  value       = aws_s3_bucket.firehose_delivery.arn
  description = "Firehose S3 bucket ARN for IAM policies"
}

output "firehose_bucket_name" {
  value       = aws_s3_bucket.firehose_delivery.id
  description = "Firehose S3 bucket name"
}

output "athena_results_bucket_name" {
  value       = aws_s3_bucket.athena_results.id
  description = "Athena query results bucket name"
}

# Redshift
output "redshift_cluster_endpoint" {
  value       = var.enable_redshift ? aws_redshift_cluster.main[0].endpoint : null
  description = "Redshift cluster endpoint for Week 7 messaging"
}

output "redshift_cluster_id" {
  value       = var.enable_redshift ? aws_redshift_cluster.main[0].cluster_identifier : null
  description = "Redshift cluster identifier"
}

output "redshift_database_name" {
  value       = var.redshift_database_name
  description = "Redshift database name for connection strings"
}

# OpenSearch
output "opensearch_domain_endpoint" {
  value       = var.enable_opensearch ? aws_opensearch_domain.logs[0].endpoint : null
  description = "OpenSearch domain endpoint for log analytics"
}

output "opensearch_domain_arn" {
  value       = var.enable_opensearch ? aws_opensearch_domain.logs[0].arn : null
  description = "OpenSearch domain ARN for IAM policies"
}

# Athena
output "athena_workgroup_name" {
  value       = aws_athena_workgroup.main.name
  description = "Athena workgroup name for query configuration"
}

# QuickSight
output "quicksight_group_arn" {
  value       = aws_quicksight_group.analysts.arn
  description = "QuickSight analysts group ARN"
}

# Summary
output "week_6_summary" {
  value = {
    kinesis_stream_created     = true
    firehose_delivery_created  = true
    kinesis_analytics_enabled  = var.enable_kinesis_analytics
    redshift_enabled           = var.enable_redshift
    redshift_nodes             = var.redshift_number_of_nodes
    opensearch_enabled         = var.enable_opensearch
    opensearch_nodes           = var.opensearch_instance_count
    athena_workgroup_created   = true
    quicksight_dashboards      = 1
    data_sources_configured    = 2
  }
  description = "Summary of all Week 6 data platform resources"
}