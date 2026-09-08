variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
}
variable "name" {
  type    = string
  default = "node-operator"
}

variable "network_mode" {
  description = "fresh creates the complete foundation network; existing manages only the reviewed public NAT edge."
  type        = string
  default     = "fresh"

  validation {
    condition     = contains(["fresh", "existing"], var.network_mode)
    error_message = "network_mode must be either fresh or existing."
  }
}

variable "existing_network" {
  description = "Existing-mode identifiers and CIDRs. These have no account-specific defaults and require review before import or apply."
  type = object({
    vpc_id                 = string
    vpc_cidr               = string
    private_subnets        = list(object({ id = string, cidr = string }))
    private_route_table_id = string
    nat_public_subnet_id   = string
    nat_public_subnet_cidr = string
    nat_public_subnet_az   = string
  })
  default = null

  validation {
    condition = var.existing_network == null ? true : (
      can(cidrnetmask(var.existing_network.vpc_cidr)) &&
      can(cidrnetmask(var.existing_network.nat_public_subnet_cidr)) &&
      length(var.existing_network.private_subnets) > 0 &&
      length(distinct([for subnet in var.existing_network.private_subnets : subnet.id])) == length(var.existing_network.private_subnets) &&
      alltrue([for subnet in var.existing_network.private_subnets : can(cidrnetmask(subnet.cidr)) && length(subnet.id) > 0]) &&
      length(var.existing_network.vpc_id) > 0 &&
      length(var.existing_network.private_route_table_id) > 0 &&
      length(var.existing_network.nat_public_subnet_id) > 0 &&
      length(var.existing_network.nat_public_subnet_az) > 0
    )
    error_message = "existing_network requires VPC/CIDR, private subnet CIDRs, a private route table, and NAT public-subnet details."
  }
}
variable "vpc_cidr" {
  type    = string
  default = "10.80.0.0/16"
}
variable "availability_zones" {
  type    = list(string)
  default = ["ap-northeast-2a", "ap-northeast-2c"]
}
variable "system_subnet_cidrs" {
  type    = list(string)
  default = ["10.80.0.0/20", "10.80.16.0/20"]
}
variable "hoodi_subnet_cidrs" {
  type    = string
  default = "10.80.32.0/20"
}
variable "public_subnet_cidr" {
  type    = string
  default = "10.80.64.0/24"
}
