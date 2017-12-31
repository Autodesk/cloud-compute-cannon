variable "access_key" {}
variable "secret_key" {}
variable "public_key" {}
variable "region" {}

# S3 required vars
variable "bucket_name" {
  default = "cloud-compute-job-data-"
}


