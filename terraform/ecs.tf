# ECS (Elastic Container Service) for FeedMe dev deployment

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = local.env.ecs.cluster_name

  configuration {
    execute_command_configuration {
      logging = "OVERRIDE"

      log_configuration {
        cloud_watch_encryption_enabled = false
        cloud_watch_log_group_name     = aws_cloudwatch_log_group.ecs_exec.name
      }
    }
  }

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = merge(local.common_tags, {
    Name = local.env.ecs.cluster_name
  })
}

# CloudWatch Log Group for ECS Exec
resource "aws_cloudwatch_log_group" "ecs_exec" {
  name              = "/aws/ecs/exec/${local.env.ecs.cluster_name}"
  retention_in_days = local.env.monitoring.log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ecs-exec-logs"
  })
}

# CloudWatch Log Group for Application Logs
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${local.env.ecs.task_family}"
  retention_in_days = local.env.monitoring.log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-app-logs"
  })
}

# ECS Task Definition
resource "aws_ecs_task_definition" "backend" {
  family                   = local.env.ecs.task_family
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = local.env.ecs.cpu
  memory                   = local.env.ecs.memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name  = local.env.ecs.container_name
      image = "${aws_ecr_repository.backend.repository_url}:${local.env.ecs.image_tag}"

      # Port Mappings
      portMappings = [
        {
          containerPort = local.env.ecs.container_port
          protocol      = "tcp"
        }
      ]

      # Environment Variables
      environment = [
        {
          name  = "NODE_ENV"
          value = "production"
        },
        {
          name  = "PORT"
          value = tostring(local.env.ecs.container_port)
        }
      ]

      # Secrets from AWS Secrets Manager
      secrets = [
        {
          name      = "MONGODB_URL"
          valueFrom = aws_secretsmanager_secret.mongodb_url.arn
        }
      ]

      # Health Check
      healthCheck = {
        command = [
          "CMD-SHELL",
          "curl -f http://localhost:${local.env.ecs.container_port}/health || exit 1"
        ]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }

      # Logging Configuration
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = local.region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      # Essential container
      essential = true

      # Resource requirements (optional for Fargate)
      # cpu    = var.ecs_cpu
      # memory = var.ecs_memory
    }
  ])

  tags = merge(local.common_tags, {
    Name = local.env.ecs.task_family
  })
}

# Secret for MongoDB URL (constructed from DocumentDB cluster)
resource "aws_secretsmanager_secret" "mongodb_url" {
  name        = "${local.name_prefix}-mongodb-url"
  description = "MongoDB connection URL for the application"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-mongodb-url"
  })
}

# MongoDB URL Secret Version
resource "aws_secretsmanager_secret_version" "mongodb_url" {
  secret_id     = aws_secretsmanager_secret.mongodb_url.id
  secret_string = "mongodb://${jsondecode(aws_secretsmanager_secret_version.docdb_credentials.secret_string)["username"]}:${urlencode(jsondecode(aws_secretsmanager_secret_version.docdb_credentials.secret_string)["password"])}@${aws_docdb_cluster.main.endpoint}:${aws_docdb_cluster.main.port}/${local.env.database.database_name}?ssl=true&tlsAllowInvalidCertificates=true&replicaSet=rs0&readPreference=secondaryPreferred&retryWrites=false"
}

# ECS Service
resource "aws_ecs_service" "backend" {
  name            = local.env.ecs.service_name
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = local.env.ecs.desired_count
  launch_type     = "FARGATE"

  # Platform version for Fargate
  platform_version = "LATEST"

  # Network Configuration
  network_configuration {
    security_groups  = [aws_security_group.ecs_tasks.id]
    subnets          = aws_subnet.private[*].id
    assign_public_ip = false
  }

  # Load Balancer Configuration
  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = local.env.ecs.container_name
    container_port   = local.env.ecs.container_port
  }

  # Service Discovery (optional)
  # service_registries {
  #   registry_arn = aws_service_discovery_service.backend.arn
  # }

  # Deployment Configuration
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  # Circuit breaker disabled for simplicity
  # deployment_circuit_breaker {
  #   enable   = true
  #   rollback = true
  # }

  # Health Check Grace Period
  health_check_grace_period_seconds = 120 # Increased for demo stability

  # Enable Execute Command for debugging
  enable_execute_command = true

  # Force new deployment when task definition changes
  force_new_deployment = true

  # Wait for steady state
  wait_for_steady_state = false

  tags = merge(local.common_tags, {
    Name = local.env.ecs.service_name
  })

  depends_on = [
    aws_lb_listener.http,
    aws_iam_role_policy.ecs_task_policy
  ]
}

# CloudWatch Alarms for ECS Service
resource "aws_cloudwatch_metric_alarm" "ecs_cpu_utilization" {
  alarm_name          = "${local.name_prefix}-ecs-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ECS CPU utilization"
  alarm_actions       = [] # Simple monitoring - notifications only

  dimensions = {
    ServiceName = aws_ecs_service.backend.name
    ClusterName = aws_ecs_cluster.main.name
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ecs-cpu-alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "ecs_memory_utilization" {
  alarm_name          = "${local.name_prefix}-ecs-high-memory"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = "85"
  alarm_description   = "This metric monitors ECS memory utilization"
  alarm_actions       = [] # Simple monitoring - notifications only

  dimensions = {
    ServiceName = aws_ecs_service.backend.name
    ClusterName = aws_ecs_cluster.main.name
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ecs-memory-alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "ecs_service_count" {
  alarm_name          = "${local.name_prefix}-ecs-low-task-count"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "RunningTaskCount"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "This metric monitors ECS running task count"
  alarm_actions       = [] # Simple monitoring - notifications only

  dimensions = {
    ServiceName = aws_ecs_service.backend.name
    ClusterName = aws_ecs_cluster.main.name
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ecs-task-count-alarm"
  })
}

# Associate managed capacity providers with cluster
resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}