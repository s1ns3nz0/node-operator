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
