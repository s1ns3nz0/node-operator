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

variable "retained_host_instance_id" {
  description = "Exact reviewed host opt-in for reconciling the legacy EBS optimization representation. Null retains the secure fresh-host default."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.retained_host_instance_id == null || var.retained_host_instance_id == "i-02c57d75e7f6810b1"
    error_message = "retained_host_instance_id must be null or the reviewed host i-02c57d75e7f6810b1."
  }
}
