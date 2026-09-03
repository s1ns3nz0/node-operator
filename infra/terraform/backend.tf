terraform {
  backend "s3" {
    bucket         = "node-operator-tfstate-106760547719-apne2"
    key            = "node-operator/t2/terraform.tfstate"
    region         = "ap-northeast-2"
    dynamodb_table = "node-operator-terraform-lock"
    encrypt        = true
  }
}
