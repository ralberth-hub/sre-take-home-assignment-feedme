# Application Auto Scaling Target
resource "aws_appautoscaling_target" "ecs_target" {
  count              = local.env.monitoring.enable_auto_recovery ? 1 : 0
  max_capacity       = 4
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.backend.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ecs-autoscaling-target"
  })
}

# Auto Scaling Policy - Scale Up on High CPU
resource "aws_appautoscaling_policy" "ecs_scale_up" {
  count              = local.env.monitoring.enable_auto_recovery ? 1 : 0
  name               = "${local.name_prefix}-ecs-scale-up"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target[0].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 70.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 300
  }

  depends_on = [aws_appautoscaling_target.ecs_target]
}

# Auto Scaling Policy - Scale Up on High Memory
resource "aws_appautoscaling_policy" "ecs_scale_up_memory" {
  count              = local.env.monitoring.enable_auto_recovery ? 1 : 0
  name               = "${local.name_prefix}-ecs-scale-up-memory"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target[0].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value       = 80.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 300
  }

  depends_on = [aws_appautoscaling_target.ecs_target]
}

# Auto Scaling Policy - Scale based on ALB Request Count
resource "aws_appautoscaling_policy" "ecs_scale_requests" {
  count              = local.env.monitoring.enable_auto_recovery ? 1 : 0
  name               = "${local.name_prefix}-ecs-scale-requests"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target[0].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.main.arn_suffix}/${aws_lb_target_group.backend.arn_suffix}"
    }
    target_value       = 100.0 # Target 100 requests per task per minute
    scale_in_cooldown  = 300
    scale_out_cooldown = 300
  }

  depends_on = [aws_appautoscaling_target.ecs_target]
}