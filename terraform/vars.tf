# Get vars from yaml based off workspace
locals {
  # Load the configuration file
  config = yamldecode(file("${path.module}/config.yaml"))

  # Extract environment-specific configuration
  env    = local.config.environments.dev # Using dev environment
  common = local.config.common

  # AWS data
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name

  # Resource naming convention
  name_prefix = local.env.deploymentname

  # Common tags to be applied to all resources
  common_tags = local.common.default_tags

  # Availability zones to use (ensure we have at least 2 for redundancy)
  azs = local.env.availability_zones

  # Construct ECR repository URL
  ecr_url = "${local.account_id}.dkr.ecr.${local.region}.amazonaws.com"
}