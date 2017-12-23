variable "subnet_ids" { type = "list" }
variable "security_group_ids" { type = "list" }
variable "redis_host" {}
variable "asg_name" {}
variable "lambda_zip_file" {
  default = "https://raw.githubusercontent.com/dionjwa/cloud-compute-cannon/${var.version}/artifacts/lambda.zip"
}

