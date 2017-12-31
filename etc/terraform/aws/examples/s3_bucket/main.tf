variable "access_key" {}
variable "secret_key" {}
variable "user" {}
variable "bucket_name" {}

variable "region" {
  default = "us-east-1"
}

module "s3" {
  source      = "../../modules/s3_bucket"
  access_key  = "${var.access_key}"
  secret_key  = "${var.secret_key}"
  region      = "${var.region}"
  bucket_name = "${var.bucket_name}"
  user        = "${var.user}"
}
