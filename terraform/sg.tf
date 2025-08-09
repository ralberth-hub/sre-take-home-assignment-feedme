# Security Groups for FeedMe dev deployment

# Security Group for Application Load Balancer
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.main.id

  # Allow HTTP traffic from anywhere
  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTPS traffic from anywhere
  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb-sg"
  })
}

# Security Group for ECS Tasks (Backend Application)
resource "aws_security_group" "ecs_tasks" {
  name        = "${local.name_prefix}-ecs-tasks-sg"
  description = "Security group for ECS tasks"
  vpc_id      = aws_vpc.main.id

  # Allow traffic from ALB on application port
  ingress {
    description     = "Traffic from ALB"
    from_port       = local.env.ecs.container_port
    to_port         = local.env.ecs.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Allow all outbound traffic (for database connections, ECR pulls, etc.)
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ecs-tasks-sg"
  })
}

# Security Group for DocumentDB
resource "aws_security_group" "documentdb" {
  name        = "${local.name_prefix}-documentdb-sg"
  description = "Security group for DocumentDB cluster"
  vpc_id      = aws_vpc.main.id

  # Allow traffic from ECS tasks on MongoDB port
  ingress {
    description     = "MongoDB from ECS tasks"
    from_port       = local.env.database.port
    to_port         = local.env.database.port
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  # Allow outbound traffic (for replication, etc.)
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-documentdb-sg"
  })
}

# Security Group for VPC Endpoints
resource "aws_security_group" "vpc_endpoint" {
  name        = "${local.name_prefix}-vpc-endpoint-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = aws_vpc.main.id

  # Allow HTTPS traffic from VPC
  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.env.vpc_cidr]
  }

  # Allow all outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc-endpoint-sg"
  })
}

# Security Group for Bastion Host (Optional - for debugging)
resource "aws_security_group" "bastion" {
  name        = "${local.name_prefix}-bastion-sg"
  description = "Security group for bastion host (debugging)"
  vpc_id      = aws_vpc.main.id

  # Allow SSH from specific IP ranges (customize as needed)
  ingress {
    description = "SSH from office/home IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    # Replace with your actual IP ranges for security
    cidr_blocks = ["0.0.0.0/0"] # WARNING: This allows SSH from anywhere - restrict in production
  }

  # Allow all outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-bastion-sg"
  })
}

# Security Group Rules for internal communication

# Allow ECS tasks to communicate with each other (if needed for service discovery)
resource "aws_security_group_rule" "ecs_internal_communication" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_tasks.id
  security_group_id        = aws_security_group.ecs_tasks.id
  description              = "Allow ECS tasks to communicate with each other"
}

# Allow DocumentDB cluster nodes to communicate with each other
resource "aws_security_group_rule" "documentdb_internal_communication" {
  type                     = "ingress"
  from_port                = local.env.database.port
  to_port                  = local.env.database.port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.documentdb.id
  security_group_id        = aws_security_group.documentdb.id
  description              = "Allow DocumentDB cluster internal communication"
}