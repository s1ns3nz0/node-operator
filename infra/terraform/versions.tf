terraform {
  required_version = ">= 1.5.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.31.0, < 6.0.0"
    }
  }
}

# This configuration intentionally has no backend. State configuration and every
# provider binary are supplied only by the separately controlled build workflow.
provider "aws" {
  region = var.aws_region
}
