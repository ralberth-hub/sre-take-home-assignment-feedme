# IAM roles and policies for FeedMe dev deployment

# ECS Task Execution Role
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${local.name_prefix}-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ecs-task-execution-role"
  })
}

# Attach the AWS managed policy for ECS task execution
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Additional policy for ECS task execution (ECR and CloudWatch Logs)
resource "aws_iam_role_policy" "ecs_task_execution_additional" {
  name = "${local.name_prefix}-ecs-task-execution-additional"
  role = aws_iam_role.ecs_task_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          aws_secretsmanager_secret.docdb_credentials.arn,
          aws_secretsmanager_secret.mongodb_url.arn
        ]
      }
    ]
  })
}

# ECS Task Role (for application-specific permissions)
resource "aws_iam_role" "ecs_task_role" {
  name = "${local.name_prefix}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ecs-task-role"
  })
}

# Policy for ECS tasks to access DocumentDB and other AWS services
resource "aws_iam_role_policy" "ecs_task_policy" {
  name = "${local.name_prefix}-ecs-task-policy"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          aws_secretsmanager_secret.docdb_credentials.arn,
          aws_secretsmanager_secret.mongodb_url.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:log-group:/ecs/${local.env.ecs.task_family}:*"
      }
    ]
  })
}

# IAM Role for Application Load Balancer (if needed for access logs)
resource "aws_iam_role" "alb_logs_role" {
  name = "${local.name_prefix}-alb-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "elasticloadbalancing.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb-logs-role"
  })
}

# Policy for ALB to write access logs to S3
resource "aws_iam_role_policy" "alb_logs_policy" {
  name = "${local.name_prefix}-alb-logs-policy"
  role = aws_iam_role.alb_logs_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetBucketAcl"
        ]
        Resource = [
          "arn:aws:s3:::${aws_s3_bucket.alb_logs.bucket}/*",
          "arn:aws:s3:::${aws_s3_bucket.alb_logs.bucket}"
        ]
      }
    ]
  })
}

# Secrets Manager Secret for DocumentDB credentials
resource "aws_secretsmanager_secret" "docdb_credentials" {
  name        = "${local.name_prefix}-docdb-credentials"
  description = "DocumentDB master user credentials"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-docdb-credentials"
  })
}

# Generate random password for DocumentDB
resource "random_password" "docdb_password" {
  length  = 16
  special = true
}

# Store DocumentDB credentials in Secrets Manager
resource "aws_secretsmanager_secret_version" "docdb_credentials" {
  secret_id = aws_secretsmanager_secret.docdb_credentials.id
  secret_string = jsonencode({
    username = "feedme_admin"
    password = random_password.docdb_password.result
  })
}