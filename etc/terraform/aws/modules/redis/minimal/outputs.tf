output "hostname" {
  value = "${aws_instance.redis.private_ip}"
}

output "security_group_id" {
  value = "${aws_security_group.redis.id}"
}

