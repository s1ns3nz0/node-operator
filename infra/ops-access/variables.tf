variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
}
variable "name" {
  type    = string
  default = "node-operator"
}
variable "vpc_id" { type = string }
variable "subnet_id" { type = string }
variable "cluster_security_group_id" { type = string }

variable "existing_ssm_endpoint_security_group_id" {
  description = "Existing shared SSM interface-endpoint security group. Set only for reviewed state migration; null creates isolated endpoints."
  type        = string
  default     = null
  nullable    = true
}

variable "manage_cluster_ingress_rule" {
  description = "Whether this root owns the host-to-EKS API ingress rule. Set false when importing a host whose rule remains baseline-owned."
  type        = bool
  default     = true
}

variable "manage_existing_endpoint_ingress_rule" {
  description = "Explicit migration opt-in when this ops state already owns its host-to-shared-endpoint ingress rule. False leaves an existing shared endpoint rule with its current external owner."
  type        = bool
  default     = false
}
