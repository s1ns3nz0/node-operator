variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
}
variable "name" {
  type    = string
  default = "node-operator"
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
