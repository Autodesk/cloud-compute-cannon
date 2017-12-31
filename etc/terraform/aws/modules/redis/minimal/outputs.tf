output "hostname" {
  value = "${aws_instance.terraform_ccc_redis.private_ip}"
}

output "security_group_id" {
  value = "${aws_security_group.terraform_ccc_redis.id}"
}

