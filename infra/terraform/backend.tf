terraform {
  backend "s3" {
    bucket         = "node-operator-tfstate-106760547719-apne2"
    key            = "node-operator/t2/terraform.tfstate"
    region         = "ap-northeast-2"
    dynamodb_table = "node-operator-terraform-lock"
    encrypt        = true
    kms_key_id     = "arn:aws:kms:ap-northeast-2:106760547719:key/23528ef1-681c-41c3-a565-d19d3ec98c37"
  }
}
