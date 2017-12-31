provider "aws" {
  access_key = "${var.access_key}"
  secret_key = "${var.secret_key}"
}

resource "random_string" "ccc-bucket-random-suffix" {
  length = 6
  upper = false
  lower = true
  number = true
  special = false
  lower = true
}

locals {
  bucket_name_internal = "${var.bucket_name == "cloud-compute-job-data-" ? "${var.bucket_name}${random_string.ccc-bucket-random-suffix.result}" : var.bucket_name}"
}

resource "aws_s3_bucket" "terraform_ccc_s3" {
  bucket = "${local.bucket_name_internal}"

  acl    = "public-read"

  policy =  <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": ["arn:aws:s3:::${local.bucket_name_internal}",
                   "arn:aws:s3:::${local.bucket_name_internal}/*"]
    }
  ]
}
EOF

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }

  force_destroy = true
}