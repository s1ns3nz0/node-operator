terraform {
  required_version = ">= 1.5.0, < 2.0.0"

  backend "s3" {
    bucket         = "node-operator-tfstate-106760547719-apne2"
    key            = "node-operator/t2/terraform.tfstate"
    region         = "ap-northeast-2"
    dynamodb_table = "node-operator-terraform-lock"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.31.0, < 6.0.0"
    }
  }
}

# State is stored in the approved encrypted S3 backend with DynamoDB locking.
# Provider binaries are still supplied only by the separately controlled build workflow.
provider "aws" {
  region = var.aws_region
}
