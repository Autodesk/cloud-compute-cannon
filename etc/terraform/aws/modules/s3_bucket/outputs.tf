output "bucket_name" {
  value = "${aws_s3_bucket.terraform_ccc_s3.id}"
}

output "domain_name" {
  value = "${aws_s3_bucket.terraform_ccc_s3.bucket_domain_name}"
}