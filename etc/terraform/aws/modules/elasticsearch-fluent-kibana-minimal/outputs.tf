output "hostname" {
  value = "${aws_instance.terraform_ccc_elasticsearch_stack_mini.public_ip}"
}
