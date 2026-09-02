variable "aws_region" {
  description = "The approved deployment region for the private EKS baseline."
  type        = string
  default     = "ap-northeast-2"

  validation {
    condition     = var.aws_region == "ap-northeast-2"
    error_message = "aws_region must be ap-northeast-2."
  }
}

variable "aws_account_id" {
  description = "Non-secret AWS account ID used only to scope resource policies."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit AWS account ID."
  }
}

variable "name" {
  description = "Short, DNS-compatible name used to namespace baseline resources."
  type        = string
  default     = "node-operator"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,38}[a-z0-9]$", var.name))
    error_message = "name must be 3-40 lowercase letters, digits, and hyphens, beginning and ending with a letter or digit."
  }
}

variable "vpc_cidr" {
  description = "The reserved VPC CIDR. This baseline intentionally does not accept arbitrary network ranges."
  type        = string
  default     = "10.80.0.0/16"

  validation {
    condition     = var.vpc_cidr == "10.80.0.0/16"
    error_message = "vpc_cidr must be the approved 10.80.0.0/16 range."
  }
}

variable "availability_zones" {
  description = "Exactly two approved Seoul availability zones for private worker subnets."
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]

  validation {
    condition     = var.availability_zones == ["ap-northeast-2a", "ap-northeast-2c"]
    error_message = "availability_zones must be [ap-northeast-2a, ap-northeast-2c]."
  }
}

variable "private_subnet_cidrs" {
  description = "Two non-public worker subnet CIDRs, one per approved availability zone."
  type        = list(string)
  default     = ["10.80.0.0/20", "10.80.16.0/20"]

  validation {
    condition     = var.private_subnet_cidrs == ["10.80.0.0/20", "10.80.16.0/20"]
    error_message = "private_subnet_cidrs must be [10.80.0.0/20, 10.80.16.0/20]."
  }
}

variable "kubernetes_version" {
  description = "EKS Kubernetes minor version. Pin deliberately in the build change that applies this baseline."
  type        = string
  default     = "1.35"

  validation {
    condition     = can(regex("^1\\.[0-9]+$", var.kubernetes_version))
    error_message = "kubernetes_version must be a Kubernetes minor version, such as 1.35."
  }
}

variable "node_instance_type" {
  description = "Approved managed-node instance type."
  type        = string
  default     = "m7i.2xlarge"

  validation {
    condition     = var.node_instance_type == "m7i.2xlarge"
    error_message = "node_instance_type must be m7i.2xlarge."
  }
}

variable "node_min_size" {
  description = "Minimum managed-node capacity."
  type        = number
  default     = 2

  validation {
    condition     = var.node_min_size == 2
    error_message = "node_min_size must remain 2 for this baseline."
  }
}

variable "node_desired_size" {
  description = "Initial managed-node capacity."
  type        = number
  default     = 2

  validation {
    condition     = var.node_desired_size == 2
    error_message = "node_desired_size must remain 2 for this baseline."
  }
}

variable "node_max_size" {
  description = "Maximum managed-node capacity."
  type        = number
  default     = 3

  validation {
    condition     = var.node_max_size == 3
    error_message = "node_max_size must remain 3 for this baseline."
  }
}

variable "node_root_volume_size" {
  description = "Encrypted gp3 root-volume size in GiB for each managed node."
  type        = number
  default     = 80

  validation {
    condition     = var.node_root_volume_size >= 40 && var.node_root_volume_size <= 200
    error_message = "node_root_volume_size must be between 40 and 200 GiB."
  }
}

variable "tags" {
  description = "Additional non-secret tags; security ownership tags cannot be overridden."
  type        = map(string)
  default     = {}
}
