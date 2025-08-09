# Provider configurations for FeedMe dev deployment

# AWS Provider Configuration
provider "aws" {
  region = local.common.aws_region

  default_tags {
    tags = local.common_tags
  }
}