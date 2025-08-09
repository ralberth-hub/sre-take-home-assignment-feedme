# Data sources for FeedMe dev deployment

# Get current AWS account ID and caller identity
data "aws_caller_identity" "current" {}

# Get current AWS region
data "aws_region" "current" {}

# Get available availability zones in the region
data "aws_availability_zones" "available" {
  state = "available"
}

# Get the default VPC (if exists) for reference
data "aws_vpc" "default" {
  default = true
}

# Get latest Amazon Linux 2 AMI for EC2 instances (if needed)
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Get ECS optimized AMI for container instances
data "aws_ami" "ecs_optimized" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-*-x86_64-ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Get current Route53 hosted zones (if any exist)
data "aws_route53_zone" "main" {
  count        = 0             # Set to 1 if you have a domain
  name         = "example.com" # Replace with your domain
  private_zone = false
}

# Get ECR authorization token for Docker operations
data "aws_ecr_authorization_token" "token" {
  registry_id = data.aws_caller_identity.current.account_id
}

# Configuration is loaded in vars.tf