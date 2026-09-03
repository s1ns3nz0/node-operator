terraform {
  required_version = ">= 1.5.0, < 2.0.0"

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
  region                      = var.aws_region
  skip_credentials_validation = var.offline_validation
  skip_metadata_api_check     = var.offline_validation
  skip_region_validation      = var.offline_validation
  skip_requesting_account_id  = var.offline_validation
}

# The replica provider is deliberately limited to the approved Tokyo DR Region.
provider "aws" {
  alias  = "audit_replica"
  region = var.audit_replica_region
}
