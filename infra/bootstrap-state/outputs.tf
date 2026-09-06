output "backend" {
  description = "Non-secret backend settings consumed by later release phases."
  value = {
    bucket         = aws_s3_bucket.state.id
    key            = "node-operator/baseline/terraform.tfstate"
    region         = var.aws_region
    dynamodb_table = aws_dynamodb_table.lock.name
    encrypt        = true
  }
}
