terraform {
  required_version = ">= 1.0"

  backend "s3" {
    region         = "ap-southeast-1"
    bucket         = "ra-tf-statefiles"
    key            = "feedme-state.tfstate"
    encrypt        = true
    dynamodb_table = "feedme"
  }

  # Always put providers here
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }

    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}