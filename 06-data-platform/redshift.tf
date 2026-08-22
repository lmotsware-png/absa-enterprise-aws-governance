# ============================================
# Redshift — Data Warehouse
# ============================================

resource "aws_redshift_cluster" "main" {
  count = var.enable_redshift ? 1 : 0

  cluster_identifier = var.redshift_cluster_name
  database_name      = var.redshift_database_name
  master_username    = var.redshift_master_username
  master_password    = random_password.redshift.result
  node_type          = var.redshift_node_type
  cluster_type       = "multi-node"
  number_of_nodes    = var.redshift_number_of_nodes

  encrypted          = true
  kms_key_id         = local.kms_s3_arn

  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.redshift_cluster_name}-final-snapshot"
  automated_snapshot_retention_period = 7

  vpc_security_group_ids = [local.data_security_group_id]
  cluster_subnet_group_name = aws_redshift_subnet_group.main.name

  iam_roles = [aws_iam_role.redshift.arn]

  tags = merge(local.common_tags, {
    Name = var.redshift_cluster_name
  })
}

resource "aws_redshift_subnet_group" "main" {
  name       = "absa-redshift-subnet-group"
  subnet_ids = local.data_subnet_ids

  tags = merge(local.common_tags, {
    Name = "ABSA-Redshift-Subnet-Group"
  })
}

resource "random_password" "redshift" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
  min_special      = 4
  min_upper        = 4
  min_lower        = 4
  min_numeric      = 4
}