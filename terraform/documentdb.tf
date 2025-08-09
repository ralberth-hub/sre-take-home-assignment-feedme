# DocumentDB (MongoDB-compatible) for FeedMe dev deployment

# DocumentDB Subnet Group
resource "aws_docdb_subnet_group" "main" {
  name       = "${local.name_prefix}-docdb-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-docdb-subnet-group"
  })
}

# DocumentDB Parameter Group
resource "aws_docdb_cluster_parameter_group" "main" {
  family      = "docdb4.0"
  name        = "${local.name_prefix}-docdb-parameter-group"
  description = "DocumentDB cluster parameter group for ${local.name_prefix}"

  # Enable TLS for security
  parameter {
    name  = "tls"
    value = "enabled"
  }

  # Set audit logging
  parameter {
    name  = "audit_logs"
    value = "enabled"
  }

  # Set profiler for performance monitoring
  parameter {
    name  = "profiler"
    value = "enabled"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-docdb-parameter-group"
  })
}

# DocumentDB Cluster
resource "aws_docdb_cluster" "main" {
  cluster_identifier = local.env.database.cluster_identifier
  engine             = "docdb"
  master_username    = jsondecode(aws_secretsmanager_secret_version.docdb_credentials.secret_string)["username"]
  master_password    = jsondecode(aws_secretsmanager_secret_version.docdb_credentials.secret_string)["password"]
  port               = local.env.database.port

  # Network and Security
  db_subnet_group_name   = aws_docdb_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.documentdb.id]

  # Parameter Group
  db_cluster_parameter_group_name = aws_docdb_cluster_parameter_group.main.name

  # Backup Configuration
  backup_retention_period = local.env.database.backup_retention_period
  preferred_backup_window = local.env.database.backup_window

  # Maintenance
  preferred_maintenance_window = "sun:03:00-sun:04:00"

  # Deletion Protection and Snapshots
  deletion_protection       = false # Set to true for production
  skip_final_snapshot       = local.env.database.skip_final_snapshot
  final_snapshot_identifier = local.env.database.skip_final_snapshot ? null : "${local.env.database.cluster_identifier}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  # Storage Encryption
  storage_encrypted = true
  kms_key_id        = aws_kms_key.docdb.arn

  # Engine Version
  engine_version = "4.0.0"

  # Enable CloudWatch Logs Exports
  enabled_cloudwatch_logs_exports = ["audit", "profiler"]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-docdb-cluster"
  })


}

# DocumentDB Cluster Instances
resource "aws_docdb_cluster_instance" "cluster_instances" {
  count              = local.env.database.instance_count
  identifier         = "${local.env.database.cluster_identifier}-${count.index + 1}"
  cluster_identifier = aws_docdb_cluster.main.id
  instance_class     = local.env.database.instance_class

  # Performance Insights not available for DocumentDB

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-docdb-instance-${count.index + 1}"
  })
}

# KMS Key for DocumentDB Encryption
resource "aws_kms_key" "docdb" {
  description             = "KMS key for DocumentDB encryption"
  deletion_window_in_days = 7

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-docdb-kms-key"
  })
}

# KMS Key Alias
resource "aws_kms_alias" "docdb" {
  name          = "alias/${local.name_prefix}-docdb"
  target_key_id = aws_kms_key.docdb.key_id
}

# CloudWatch Log Groups for DocumentDB
resource "aws_cloudwatch_log_group" "docdb_audit" {
  name              = "/aws/docdb/${aws_docdb_cluster.main.cluster_identifier}/audit"
  retention_in_days = local.env.monitoring.log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-docdb-audit-logs"
  })
}

resource "aws_cloudwatch_log_group" "docdb_profiler" {
  name              = "/aws/docdb/${aws_docdb_cluster.main.cluster_identifier}/profiler"
  retention_in_days = local.env.monitoring.log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-docdb-profiler-logs"
  })
}

# CloudWatch Alarms for DocumentDB Monitoring
resource "aws_cloudwatch_metric_alarm" "docdb_cpu_utilization" {
  alarm_name          = "${local.name_prefix}-docdb-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/DocDB"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors DocumentDB CPU utilization"
  alarm_actions       = [] # Add SNS topic ARN for notifications

  dimensions = {
    DBClusterIdentifier = aws_docdb_cluster.main.cluster_identifier
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-docdb-cpu-alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "docdb_database_connections" {
  alarm_name          = "${local.name_prefix}-docdb-high-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/DocDB"
  period              = "300"
  statistic           = "Average"
  threshold           = "50" # Adjust based on your connection pool size
  alarm_description   = "This metric monitors DocumentDB connection count"
  alarm_actions       = [] # Add SNS topic ARN for notifications

  dimensions = {
    DBClusterIdentifier = aws_docdb_cluster.main.cluster_identifier
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-docdb-connections-alarm"
  })
}

# Output the DocumentDB connection string (without credentials)
locals {
  docdb_endpoint = aws_docdb_cluster.main.endpoint
  docdb_port     = aws_docdb_cluster.main.port

  # MongoDB connection string for application
  mongodb_connection_string = "mongodb://${aws_docdb_cluster.main.endpoint}:${aws_docdb_cluster.main.port}/${local.env.database.database_name}?ssl=true&replicaSet=rs0&readPreference=secondaryPreferred&retryWrites=false"
}